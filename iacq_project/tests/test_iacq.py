"""
Tests unitaires de l’interface IACQ dans le cadre du projet
de communication sécurisée avec un FPGA.

Auteurs :
- AHNANI Ali <ahnaniali@gmail.com>
- Khalid ELKOUSSAMI <khalid.elkoussami@etu.emse.fr>

Date : 25/03/2026

Encadrants :
- Jean-Baptiste RIGAUD <jean-baptiste.rigaud@emse.fr>
- Olivier POTIN <olivier.potin@emse.fr>
- Raphael VIERA <raphael.viera@emse.fr>

Description :
Ce fichier contient des tests unitaires permettant de vérifier le bon
fonctionnement de l’interface IACQ, de la communication avec l’émulateur
FPGA, des validations d’entrée, du chargement des trames depuis un fichier
CSV, ainsi que du cycle complet chiffrement/déchiffrement.
"""

import unittest
import sys
import os

# S’assure que le dossier parent est présent dans le chemin d’import
# afin de pouvoir importer correctement les modules du projet
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from iacq import IACQ
from exceptions import FPGAConnectionError, FPGAValidationError


class TestIACQ(unittest.TestCase):
    """Classe de tests unitaires pour l’interface IACQ."""

    def setUp(self):
        """Prépare les données de test et initialise le système IACQ avec l’émulateur."""
        self.key = bytes.fromhex("8A55114D1CB6A9A2BE263D4D7AECAAFF")
        self.nonce = bytes.fromhex("4ED0EC0B98C529B7C8CDDF37BCD0284A")
        self.associated_data = bytes.fromhex("4120746F20428000")
        self.system = IACQ(port="VIRTUAL", emulator=True)
        
    def test_connect_fpga(self):
        """Vérifie que la connexion à l’émulateur FPGA s’ouvre correctement."""
        self.system.open()
        self.assertTrue(self.system.connection.is_open, "L’émulateur FPGA devrait être connecté")
        
    def test_send_to_fpga(self):
        """Vérifie qu’un envoi de commande vers le FPGA ne provoque pas d’exception."""
        self.system.open()
        # Ne doit pas lever d’exception
        try:
            self.system.send_command(b"\x54", b"Valid Encrypted Sequence")
        except Exception as e:
            self.fail(f"send_command a levé une exception : {e}")
            
    def test_send_to_fpga_unconnected(self):
        """Vérifie qu’une erreur est levée si une commande est envoyée sans connexion."""
        with self.assertRaises(FPGAConnectionError):
            self.system.send_command(b"\x54", b"Should fail")
            
    def test_input_validations(self):
        """Vérifie les validations sur les types et les longueurs des données d’entrée."""
        self.system.open()
        # Types invalides
        with self.assertRaisesRegex(FPGAValidationError, "Key must be bytes"):
            self.system.send_key("not a byte string")
        with self.assertRaisesRegex(FPGAValidationError, "Nonce must be bytes"):
            self.system.send_nonce("not a byte string")
            
        # Longueurs invalides
        with self.assertRaisesRegex(FPGAValidationError, "Key must be 16 bytes"):
            self.system.send_key(b"too_short")
        with self.assertRaisesRegex(FPGAValidationError, "Nonce must be 16 bytes"):
            self.system.send_nonce(b"way_too_long_for_a_nonce_123456789")
        with self.assertRaisesRegex(FPGAValidationError, "Associated data must be at most 8 bytes"):
            self.system.send_associated_data(b"bad_len" * 2)
        with self.assertRaisesRegex(FPGAValidationError, "Waveform must be 181 bytes"):
            self.system.send_waveform_to_fpga(b"not_181_bytes_long" * 5)
            
    def test_read_trames_from_csv(self):
        """
        Vérifie la lecture des trames depuis un fichier CSV temporaire.
        Un fichier factice est créé afin de garantir le bon déroulement du test
        quel que soit l’environnement d’exécution.
        """
        # Écriture temporaire d’un CSV factice pour garantir le bon fonctionnement du test
        test_file = "waveform_example_ecg.csv"
        # 181 octets = 362 caractères hexadécimaux
        dummy_trame = "AB" * 181
        with open(test_file, "w") as f:
            f.write(dummy_trame + "\n")
            
        trames = self.system.read_trames_from_csv(test_file)
        self.assertEqual(len(trames), 1)
        self.assertEqual(len(trames[0]), 181)
        
        # Nettoyage
        if os.path.exists(test_file):
            os.remove(test_file)
            
    def test_individual_protocol_commands(self):
        """Teste séparément chaque commande du protocole pour vérifier
        qu’elles encodent correctement les données, ajoutent le bourrage
        nécessaire et retirent correctement les résultats."""
        self.system.open()
        
        # 1. send_key
        resp = self.system.send_key(self.key)
        self.assertEqual(resp.rstrip(b"\n"), b"OK")
        
        # 2. send_nonce
        resp = self.system.send_nonce(self.nonce)
        self.assertEqual(resp.rstrip(b"\n"), b"OK")
        
        # 3. send_associated_data
        resp = self.system.send_associated_data(self.associated_data)
        self.assertEqual(resp.rstrip(b"\n"), b"OK")
        
        # 4. send_waveform_to_fpga
        dummy_waveform = b"A" * 181
        resp = self.system.send_waveform_to_fpga(dummy_waveform)
        self.assertEqual(resp.rstrip(b"\n"), b"OK")
        
        # 5. start_encryption
        resp = self.system.start_encryption()
        self.assertEqual(resp.rstrip(b"\n"), b"OK")
        
        # 6. get_tag
        tag_resp = self.system.get_tag()
        self.assertEqual(len(tag_resp), 16)
        
        # 7. get_ciphertext
        cipher_resp = self.system.get_ciphertext()
        self.assertEqual(len(cipher_resp), 184)
        
    def test_encrypt_decrypt_roundtrip(self):
        """Teste de bout en bout : chiffrement sur l’émulateur FPGA,
        déchiffrement en Python, puis vérification de la correspondance.

        Ce test reproduit l’utilisation réelle du protocole UART avec le FPGA :
        1. Envoi de la clé, du nonce, des données associées et de la forme d’onde
           via le protocole (le bourrage est appliqué par iacq.py)
        2. Déclenchement du chiffrement sur le FPGA
        3. Récupération du texte chiffré sur 184 octets et du tag sur 16 octets
        4. Déchiffrement en Python avec ascon_pcsn
        5. Vérification que la sortie déchiffrée est identique à la forme d’onde
           originale de 181 octets
        """
        self.system.open()
        
        original_waveform = b"\xAB" * 181  # forme d’onde de test sur 181 octets
        ad_raw = b"A to B"
        
        # Étapes 1 à 3 : chiffrement sur le FPGA
        ciphertext, tag = self.system.encrypt_on_fpga(
            waveform=original_waveform,
            key=self.key,
            nonce=self.nonce,
            associated_data=ad_raw
        )
        
        # Vérification des tailles
        self.assertEqual(len(ciphertext), 184, "Le texte chiffré doit faire 184 octets (avec bourrage)")
        self.assertEqual(len(tag), 16, "Le tag doit faire 16 octets")
        self.assertNotEqual(ciphertext[:181], original_waveform, "Le texte chiffré doit être différent du texte clair")
        
        # Étapes 4 et 5 : déchiffrement en Python et vérification
        decrypted = self.system.decrypt_waveform(
            ciphertext, tag, self.key, self.nonce, ad_raw
        )
        
        self.assertEqual(len(decrypted), 181, "La sortie déchiffrée doit faire 181 octets")
        self.assertEqual(decrypted, original_waveform, "La forme d’onde déchiffrée doit correspondre à l’original")
        
    def tearDown(self):
        """Ferme proprement le système après chaque test."""
        self.system.close()


if __name__ == "__main__":
    unittest.main()