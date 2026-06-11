"""
Script de démonstration du chiffrement et du déchiffrement d’un signal
(par exemple une forme d’onde ECG) avec l’algorithme Ascon.

Auteurs :
- AHNANI Ali <ahnaniali@gmail.com>
- Khalid ELKOUSSAMI <khalid.elkoussami@etu.emse.fr>

Description :
Ce fichier charge une forme d’onde depuis un fichier CSV, applique un
chiffrement authentifié avec Ascon, vérifie ensuite le déchiffrement,
puis affiche une visualisation comparative du signal original, du signal
chiffré et du signal déchiffré.
"""

from ascon_pcsn import ascon_encrypt, ascon_decrypt
import matplotlib.pyplot as plt
import os

# Paramètres de chiffrement
# Utiliser exactement ces valeurs pour une comparaison FPGA ultérieure
key = bytes.fromhex("8A55114D1CB6A9A2BE263D4D7AECAAFF")
nonce = bytes.fromhex("4ED0EC0B98C529B7C8CDDF37BCD0284A")
associated_data = b"A to B"

def load_waveform_from_csv(csv_path="data/xNorm.csv", index=0):
    """Charge une seule forme d’onde depuis le fichier CSV."""
    if not os.path.exists(csv_path):
        # Repli vers le répertoire local si le script est exécuté depuis un autre emplacement
        csv_path = "xNorm.csv"
        
    with open(csv_path, "r") as f:
        for i, line in enumerate(f):
            if i == index:
                return bytes.fromhex(line.strip())
    raise ValueError(f"Waveform index {index} not found")

print("Étape 2 : Chargement d’une forme d’onde")
waveform = load_waveform_from_csv(index=0)
print(f"Waveform: {len(waveform)} bytes")  # Doit être égal à 181

print("\nÉtape 3 : Chiffrement")
# ascon_encrypt renvoie le texte chiffré avec le tag concaténé à la fin
encrypted_payload = ascon_encrypt(key, nonce, associated_data, waveform)

# Séparation du texte chiffré et du tag de 16 octets
ciphertext = encrypted_payload[:-16]
tag = encrypted_payload[-16:]

print(f"Ciphertext: {len(ciphertext)} bytes")
print(f"Tag: {tag.hex()}")
print(f"First 10 bytes (hex): {ciphertext[:10].hex()}")

print("\nÉtape 4 : Déchiffrement")
# ascon_decrypt attend la charge utile concaténée (texte chiffré + tag)
decrypted = ascon_decrypt(key, nonce, associated_data, encrypted_payload)

if decrypted == waveform:
    print("SUCCESS: Decrypted data matches original!")
else:
    print("ERROR: Data mismatch")

print("\nÉtape 5 : Visualisation")
fig, axes = plt.subplots(3, 1, figsize=(12, 8))

# Signal original
axes[0].plot(list(waveform), color="blue")
axes[0].set_title("Original ECG Waveform")
axes[0].set_ylabel("Amplitude")

# Texte chiffré
# Le résultat doit ressembler à du bruit
axes[1].plot(list(ciphertext), color="red")
axes[1].set_title("Encrypted (Ciphertext)")
axes[1].set_ylabel("Amplitude")

# Signal déchiffré
# Il doit correspondre au signal original
axes[2].plot(list(decrypted), color="green")
axes[2].set_title("Decrypted (Recovered)")
axes[2].set_ylabel("Amplitude")
axes[2].set_xlabel("Sample")

plt.tight_layout()
plt.savefig("demo_plot.png")
print("Plot saved as demo_plot.png. Displaying visualization (Close window to exit)...")
plt.show(block=False)
plt.pause(2.0)  # Affichage pendant 2 secondes dans les environnements de test
plt.close()