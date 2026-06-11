"""
Interface de communication IACQ avec le FPGA pour l’acquisition ECG
chiffrée avec ASCON-128.

Auteurs :
- AHNANI Ali <ahnaniali@gmail.com>
- Khalid ELKOUSSAMI <khalid.elkoussami@etu.emse.fr>

Date : 25/03/2026

Encadrants :
- Jean-Baptiste RIGAUD <jean-baptiste.rigaud@emse.fr>
- Olivier POTIN <olivier.potin@emse.fr>
- Raphael VIERA <raphael.viera@emse.fr>

Description :
Ce fichier implémente l’interface de communication entre un programme Python
et un FPGA (ou son émulateur) dans le cadre d’une acquisition sécurisée de
signaux ECG. Il permet d’envoyer les paramètres cryptographiques, les données
associées et les trames ECG au FPGA, de déclencher le chiffrement ASCON-128,
de récupérer le texte chiffré et le tag d’authentification, puis d’effectuer
le déchiffrement côté Python à l’aide de l’implémentation de référence.

Protocole (identique à l’implémentation de référence) :
    K (0x4B) : envoyer la clé de 16 octets
    N (0x4E) : envoyer le nonce de 16 octets
    A (0x41) : envoyer 8 octets de données associées - 6 octes + 0x80 00
    W (0x57) : envoyer 184 octets de forme d’onde - 181 octets + bourrage 0x80 0x00 0x00
    G (0x47) : démarrer le chiffrement
    T (0x54) : récupérer le tag     -> resp[:-3] supprime "OK\\n"         -> 16 octets
    C (0x43) : récupérer le chiffré -> resp[:-6] supprime "800000OK\\n"   -> 181 octets

Déchiffrement :
    ascon_decrypt(key, nonce, b"A to B", ciphertext + tag)
    Le FPGA et l’émulateur chiffrent tous deux avec les données associées
    brutes (b"A to B") en interne.
    Il faut donc passer directement b"A to B" à decrypt_waveform,
    sans retraitement supplémentaire.
"""

import os
import csv
import time
import logging

import pandas as pd
from scipy.signal import butter, filtfilt

from fpga_emulator import FPGAEmulator
from ascon_pcsn import ascon_decrypt
from exceptions import (
    FPGAConnectionError, FPGAValidationError,
    FPGAAuthenticationError, EncryptionError,
    FPGATimeoutError, FPGAProtocolError
)

logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('fpga_communication.log', encoding='utf-8'),
        logging.StreamHandler()
    ]
)


# ---------------------------------------------------------------------------
# Filtres de signal
# ---------------------------------------------------------------------------

def high_pass_filter(data, cutoff=0.5, fs=500.0, order=5):
    """Applique un filtre passe-haut au signal."""
    nyquist = 0.5 * fs
    b, a = butter(order, cutoff / nyquist, btype='high')
    return filtfilt(b, a, data)


def low_pass_filter(data, cutoff=50.0, fs=500.0, order=5):
    """Applique un filtre passe-bas au signal."""
    nyquist = 0.5 * fs
    b, a = butter(order, cutoff / nyquist, btype='low')
    return filtfilt(b, a, data)


# ---------------------------------------------------------------------------
# Classe IACQ
# ---------------------------------------------------------------------------

class IACQ:
    def __init__(self, port: str, baud_rate: int = 115200,
                 timeout: float = 2, emulator: bool = False, max_retries: int = 3):
        """
        Initialise l’interface IACQ.

        Args:
            port: port série (ex. 'COM8') ou 'VIRTUAL' pour l’émulateur.
            baud_rate: débit UART en bauds (115200 par défaut).
            timeout: délai maximal de lecture pyserial en secondes (2 par défaut).
            emulator: si True, utilise FPGAEmulator au lieu du matériel réel.
            max_retries: nombre maximal de tentatives en cas d’échec de communication.
        """
        self.port         = port
        self.baud_rate    = baud_rate
        self.timeout      = timeout
        self.use_emulator = emulator
        self.max_retries  = max_retries
        self.connection   = None
        logging.info(f"IACQ initialized — port={port}, baud={baud_rate}, emulator={emulator}")

    # -----------------------------------------------------------------------
    # Gestion de la connexion
    # -----------------------------------------------------------------------

    def open(self):
        """Ouvre la connexion série vers le FPGA ou vers l’émulateur."""
        try:
            if self.use_emulator:
                self.connection = FPGAEmulator(
                    port=self.port, baud_rate=self.baud_rate, timeout=self.timeout
                )
                self.connection.open()
                logging.info("Connected to FPGA emulator.")
            else:
                import serial
                self.connection = serial.Serial(
                    self.port, self.baud_rate, timeout=self.timeout
                )
                logging.info(f"Connected to hardware on {self.port}.")
        except Exception as e:
            logging.error(f"Connection error: {e}")
            raise FPGAConnectionError(f"Failed to connect: {e}")

    def close(self):
        """Ferme la connexion série."""
        if self.connection and getattr(self.connection, 'is_open', True):
            try:
                self.connection.close()
            except Exception as e:
                logging.debug(f"Ignoring error during close: {e}")
            logging.info("Connection closed.")

    def reconnect(self, retries: int = 3, delay: float = 2.0):
        """Tente de rétablir la connexion en la fermant puis en la rouvrant."""
        logging.warning("Initiating connection recovery (reconnect)...")
        self.close()
        for attempt in range(1, retries + 1):
            time.sleep(delay)
            try:
                self.open()
                logging.info(f"Reconnected successfully on attempt {attempt}.")
                return
            except FPGAConnectionError as e:
                logging.warning(f"Reconnect attempt {attempt}/{retries} failed: {e}")
        
        raise FPGAConnectionError(f"Exhausted all {retries} connection recovery attempts.")

    def __enter__(self):
        self.open()
        return self

    def __exit__(self, *_):
        self.close()

    # -----------------------------------------------------------------------
    # Chargement des données
    # -----------------------------------------------------------------------

    def load_data(self, filepath: str) -> pd.DataFrame:
        """Charge les données ECG depuis un fichier CSV dans un DataFrame."""
        if not os.path.exists(filepath):
            raise FileNotFoundError(f"Data file not found: {filepath}")
        logging.info(f"Loading data from {filepath}...")
        return pd.read_csv(filepath)

    def read_trames_from_csv(self, filepath: str) -> list:
        """
        Lit des trames de forme d’onde depuis un fichier CSV.
        Chaque ligne doit contenir une chaîne hexadécimale
        (les espaces sont autorisés).
        Retourne une liste d’objets bytes.
        """
        if not os.path.exists(filepath):
            raise FileNotFoundError(f"Data file not found: {filepath}")
        trames = []
        with open(filepath, newline='', encoding='utf-8') as f:
            for row in csv.reader(f):
                if not row:
                    continue
                hex_str = ''.join(row).replace(' ', '')
                try:
                    trames.append(bytes.fromhex(hex_str))
                    logging.debug(f"Read trame: {hex_str}")
                except ValueError:
                    logging.warning(f"Ignored invalid hex string: {hex_str}")
        return trames

    # -----------------------------------------------------------------------
    # Primitives UART (miroir exact du send_command / receive_response de référence)
    # -----------------------------------------------------------------------

    def send_command(self, command: bytes, data: bytes = b'') -> bytes:
        """
        Envoie une commande suivie éventuellement de données,
        attend 0,1 s puis lit la réponse.
        Inclut une logique de nouvelle tentative basée sur self.max_retries.
        """
        if not self.connection or not getattr(self.connection, 'is_open', True):
            raise FPGAConnectionError("Not connected to FPGA.")
        msg = command + data
        
        last_exception = None
        for attempt in range(1, self.max_retries + 1):
            try:
                if attempt > 1:
                    logging.info(f"TX '{chr(command[0])}' - Retry {attempt}/{self.max_retries}")
                else:
                    logging.info(f"TX '{chr(command[0])}' ({len(msg)} bytes)")
                    logging.debug(f"TX hex: {msg.hex()}")
                
                # Vide le tampon d’entrée pour éliminer les données parasites avant l’envoi
                if hasattr(self.connection, 'reset_input_buffer'):
                    self.connection.reset_input_buffer()
                    
                self.connection.write(msg)
                time.sleep(2)
                return self.receive_response()
            except FPGATimeoutError as e:
                last_exception = e
                logging.warning(f"Timeout on RX, attempt {attempt}/{self.max_retries}")
                time.sleep(2)  # Délai d’attente avant une nouvelle tentative
            except FPGAProtocolError as e:
                last_exception = e
                logging.warning(f"Protocol error, attempt {attempt}/{self.max_retries}: {e}")
                time.sleep(2)
                
        raise last_exception or FPGATimeoutError(f"Max retries ({self.max_retries}) exhausted for send_command.")

    def receive_response(self) -> bytes:
        """
        Lit la réponse du FPGA ou de l’émulateur.
        Vérifie le format de la réponse ('OK\\n').
        """
        if not self.connection or not getattr(self.connection, 'is_open', True):
            raise FPGAConnectionError("Not connected to FPGA.")
        time.sleep(1)
        response = self.connection.read(200)
        
        if not response:
            raise FPGATimeoutError("Empty response received from FPGA (timeout).")
            
        logging.debug(f"RX {len(response)} bytes: {response.hex()}")
        
        # Vérifie la présence de l’accusé de réception 'OK\n' ou équivalent
        if not response.endswith(b"OK\n"):
            raise FPGAProtocolError(
                f"Invalid response format: missing 'OK\\n' acknowledgment. "
                f"Raw hex: {response.hex()}"
            )
            
        return response

    # -----------------------------------------------------------------------
    # Envoi des paramètres
    # -----------------------------------------------------------------------

    def send_key(self, key: bytes) -> bytes:
        """Envoie une clé de 16 octets — commande 0x4B ('K')."""
        if not isinstance(key, bytes) or len(key) != 16:
            raise FPGAValidationError(f"Key must be 16 bytes, got {len(key)}")
        return self.send_command(bytes([0x4B]), key)

    def send_nonce(self, nonce: bytes) -> bytes:
        """Envoie un nonce de 16 octets — commande 0x4E ('N')."""
        if not isinstance(nonce, bytes) or len(nonce) != 16:
            raise FPGAValidationError(f"Nonce must be 16 bytes, got {len(nonce)}")
        return self.send_command(bytes([0x4E]), nonce)

    def send_associated_data(self, assoc_data: bytes) -> bytes:
        """
        Envoie les données associées — commande 0x41 ('A').
        Le FPGA attend exactement 8 octets, envoyés tels quels.
        Passer par exemple :
        bytes.fromhex("4120746F20428000"), soit b"A to B" + 0x80 0x00
        """
        if not isinstance(assoc_data, bytes):
            raise FPGAValidationError("Associated data must be bytes.")
        if len(assoc_data) != 8:
            raise FPGAValidationError(f"Associated data must be 8 bytes, got {len(assoc_data)}")
        logging.debug(f"AD: {assoc_data.hex()} ({len(assoc_data)} bytes)")
        return self.send_command(bytes([0x41]), assoc_data)

    def send_waveform_to_fpga(self, waveform: bytes) -> bytes:
        """
        Envoie la forme d’onde — commande 0x57 ('W').
        Ajoute le bourrage ASCON 0x80 0x00 0x00 à la forme d’onde brute
        de 181 octets.
        Total envoyé : 184 octets.
        La forme d’onde de référence se termine par : ... 52 80 00 00
        """
        if not isinstance(waveform, bytes) or len(waveform) != 181:
            raise FPGAValidationError(f"Waveform must be 181 bytes, got {len(waveform)}")
        padded = waveform + bytes.fromhex("800000")
        logging.debug(f"Waveform TX: {len(padded)} bytes (181 + 800000 padding)")
        return self.send_command(bytes([0x57]), padded)

    def start_encryption(self) -> bytes:
        """Déclenche le chiffrement ASCON-128 — commande 0x47 ('G')."""
        return self.send_command(bytes([0x47]))

    # -----------------------------------------------------------------------
    # Récupération des résultats
    # -----------------------------------------------------------------------

    def get_tag(self) -> bytes:
        """
        Récupère le tag d’authentification — commande 0x54 ('T').
        Réponse brute : <16 octets> + 'OK' + '\\n' = 19 octets
        Retourne le tag sur 16 octets.
        Référence : tag_clean = tag[:-3]
        """
        resp = self.send_command(bytes([0x54]))
        tag = resp[:-3]
        logging.debug(f"Tag ({len(tag)} bytes): {tag.hex()}")
        return tag

    def get_ciphertext(self) -> bytes:
        """
        Récupère le texte chiffré — commande 0x43 ('C').
        Réponse brute : <181 octets chiffrés> + 0x800000 + 'OK' + '\\n' = 187 octets
        Retourne 181 octets de texte chiffré.
        Référence : cipher_clean = ciphertext[:-6]
        """
        resp = self.send_command(bytes([0x43]))
        ciphertext = resp[:-6]
        logging.info(f"Ciphertext ({len(ciphertext)} bytes)")
        logging.debug(f"CT: {ciphertext.hex()}")
        return ciphertext

    # -----------------------------------------------------------------------
    # Chiffrement / déchiffrement de haut niveau
    # -----------------------------------------------------------------------

    def encrypt_on_fpga(self, waveform: bytes, key: bytes,
                        nonce: bytes, associated_data: bytes):
        """
        Exécute un cycle complet de chiffrement ASCON-128 sur le FPGA.

        Args:
            waveform: forme d’onde ECG brute de 181 octets.
                      send_waveform_to_fpga() ajoute 0x80 0x00 0x00
                      pour envoyer 184 octets.
            key: clé de chiffrement de 16 octets.
            nonce: nonce de 16 octets.
            associated_data: données associées brutes (ex. b"A to B").
                             send_associated_data() complète les données
                             pour le FPGA.
                             decrypt_waveform() transmet cette valeur
                             directement à ascon_decrypt.

        Returns:
            (ciphertext: bytes [181], tag: bytes [16])
        """
        try:
            self.send_key(key)
            self.send_nonce(nonce)
            self.send_associated_data(associated_data)
            self.send_waveform_to_fpga(waveform)
            self.start_encryption()
            tag        = self.get_tag()
            ciphertext = self.get_ciphertext()
            logging.info(f"Encryption OK — tag: {tag.hex()}, CT: {len(ciphertext)} bytes")
            return ciphertext, tag
        except Exception as e:
            logging.error(f"Encryption failed: {e}")
            raise EncryptionError(f"Hardware interaction failed: {e}")

    def decrypt_waveform(self, ciphertext: bytes, tag: bytes,
                         key: bytes, nonce: bytes,
                         associated_data: bytes) -> bytes:
        """
        Déchiffre le texte chiffré du FPGA à l’aide de la référence Python ASCON-128.

        Il faut passer les données associées brutes (par ex. b"A to B"),
        c’est-à-dire la même valeur utilisée par le FPGA réel et l’émulateur
        après suppression de leur bourrage interne.

        ascon_decrypt(key, nonce, associated_data, ciphertext + tag)

        Args:
            ciphertext: 181 octets issus de get_ciphertext().
            tag: 16 octets issus de get_tag().
            key: clé de 16 octets.
            nonce: nonce de 16 octets.
            associated_data: données associées brutes (ex. b"A to B").

        Returns:
            Texte en clair déchiffré (181 octets).

        Raises:
            FPGAAuthenticationError: si la vérification du tag échoue.
        """
        try:
            logging.debug(f"Decrypt | key  : {key.hex()}")
            logging.debug(f"Decrypt | nonce: {nonce.hex()}")
            logging.debug(f"Decrypt | AD   : {associated_data!r}")
            logging.debug(f"Decrypt | CT   : {len(ciphertext)} bytes | {ciphertext[:16].hex()}...")
            logging.debug(f"Decrypt | tag  : {tag.hex()}")

            decrypted = ascon_decrypt(
                key, nonce, associated_data, ciphertext + tag, variant="Ascon-128"
            )

            if decrypted is None:
                raise FPGAAuthenticationError(
                    "Authentication failed: tag mismatch or corrupted payload."
                )

            logging.info(f"Decryption OK — {len(decrypted)} bytes")
            return decrypted

        except FPGAAuthenticationError:
            raise
        except Exception as e:
            logging.error(f"Decryption error: {e}")
            raise FPGAAuthenticationError(f"Authentication failed: {e}")