"""
Tests unitaires du chiffrement et du déchiffrement ASCON
dans le cadre du projet IACQ.

Auteurs :
- AHNANI Ali <ahnaniali@gmail.com>
- Khalid ELKOUSSAMI <khalid.elkoussami@etu.emse.fr>

Date : 25/03/2026

Encadrants :
- Jean-Baptiste RIGAUD <jean-baptiste.rigaud@emse.fr>
- Olivier POTIN <olivier.potin@emse.fr>
- Raphael VIERA <raphael.viera@emse.fr>

Description :
Ce fichier contient un test unitaire vérifiant le bon fonctionnement
du chiffrement et du déchiffrement avec ASCON. Il contrôle qu’un message
chiffré est bien différent du texte clair d’origine, puis vérifie que
le déchiffrement permet de retrouver exactement le message initial.
"""

import unittest
import sys
import os

# Ajoute le dossier parent au chemin de recherche des modules
# afin de permettre l’import des fichiers du projet
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from ascon_pcsn import ascon_encrypt, ascon_decrypt


class TestEncryption(unittest.TestCase):
    """Classe de test unitaire pour les fonctions de chiffrement ASCON."""

    def test_encrypt_decrypt(self):
        """Vérifie qu’un message chiffré puis déchiffré reste identique à l’original."""
        key = b"TEST_KEY_1234567"
        nonce = b"TEST_NONCE_12345"
        plaintext = b"Sensible Medical Data"
        associated_data = b""
        
        # Transformation du texte clair en texte chiffré
        ciphertext = ascon_encrypt(key, nonce, associated_data, plaintext)
        self.assertNotEqual(plaintext, ciphertext, "Le texte chiffré ne doit pas être identique au texte clair")
        
        # Transformation du texte chiffré en texte clair
        decrypted = ascon_decrypt(key, nonce, associated_data, ciphertext)
        
        self.assertEqual(plaintext, decrypted, "Le message déchiffré doit être identique au texte clair d’origine")


if __name__ == "__main__":
    unittest.main()