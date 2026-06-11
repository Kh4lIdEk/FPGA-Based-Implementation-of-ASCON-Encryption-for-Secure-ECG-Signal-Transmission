#!/usr/bin/env python3

"""
Implémentation d'Ascon v1.2, un algorithme cryptographique
de chiffrement authentifié et de hachage.
Référence : http://ascon.iaik.tugraz.at/

Auteur : 
- AHNANI Ali <ahnaniali@gmail.com>; 
-Khalid ELKOUSSAMI <khalid.elkoussami@etu.emse.fr>
Date : 25/03/2026

Encadrants :
- Jean-Baptiste RIGAUD <jean-baptiste.rigaud@emse.fr>
- Olivier POTIN <olivier.potin@emse.fr>
- Raphael VIERA <raphael.viera@emse.fr>

Description :
Ce fichier implémente les principales fonctionnalités de l’algorithme Ascon v1.2 :
- le chiffrement authentifié (AEAD),
- le déchiffrement avec vérification d’intégrité,
- le hachage et le mode XOF,
- ainsi que les fonctions internes nécessaires comme la permutation,
  l’initialisation, le traitement des données associées et la finalisation.

Le fichier contient également des fonctions de démonstration permettant
de tester le chiffrement et le hachage.
"""

debug = True
debugpermutation = True
debugtransformation = True
debugFull = False

# === Fonctions de hachage / XOF Ascon ===

def ascon_hash(message, variant="Ascon-Hash", hashlength=32): 
    """
    Fonction de hachage Ascon et fonction à sortie extensible (XOF).
    message : objet bytes de longueur arbitraire
    variant : "Ascon-Hash", "Ascon-Hasha" (sortie de 256 bits pour une sécurité de 128 bits),
              "Ascon-Xof" ou "Ascon-Xofa" (sortie de longueur arbitraire,
              sécurité = min(128, taille_en_bits/2))
    hashlength : longueur de sortie demandée en octets
                 (doit valoir 32 pour "Ascon-Hash" ;
                 peut être arbitraire pour Ascon-Xof, mais devrait être >= 32
                 pour garantir 128 bits de sécurité)
    retourne : un objet bytes contenant l’empreinte de hachage
    """
    assert variant in ["Ascon-Hash", "Ascon-Hasha", "Ascon-Xof", "Ascon-Xofa"]
    if variant in ["Ascon-Hash", "Ascon-Hasha"]: assert(hashlength == 32)
    a = 12   # nombre de tours
    b = 8 if variant in ["Ascon-Hasha", "Ascon-Xofa"] else 12
    rate = 8 # débit en octets

    # Initialisation
    tagspec = int_to_bytes(256 if variant in ["Ascon-Hash", "Ascon-Hasha"] else 0, 4)
    S = bytes_to_state(to_bytes([0, rate * 8, a, a-b]) + tagspec + zero_bytes(32))
    if debug: printstate(S, "initial value:")

    ascon_permutation(S, a)
    if debug: printstate(S, "initialization:")

    # Traitement du message (phase d’absorption)
    m_padding = to_bytes([0x80]) + zero_bytes(rate - (len(message) % rate) - 1)
    m_padded = message + m_padding

    # Premiers blocs sauf le dernier
    for block in range(0, len(m_padded) - rate, rate):
        S[0] ^= bytes_to_int(m_padded[block:block+8])  # rate=8
        ascon_permutation(S, b)
    # Dernier bloc
    block = len(m_padded) - rate
    S[0] ^= bytes_to_int(m_padded[block:block+8])  # rate=8
    if debug: printstate(S, "process message:")

    # Finalisation (phase d’extraction / squeezing)
    H = b""
    ascon_permutation(S, a)
    while len(H) < hashlength:
        H += int_to_bytes(S[0], 8)  # rate=8
        ascon_permutation(S, b)
    if debug: printstate(S, "finalization:")
    return H[:hashlength]


# === Chiffrement et déchiffrement AEAD Ascon ===

def ascon_encrypt(key, nonce, associateddata, plaintext, variant="Ascon-128"): 
    """
    Fonction de chiffrement Ascon.
    key : objet bytes de taille 16 (pour Ascon-128, Ascon-128a ; sécurité 128 bits)
          ou 20 (pour Ascon-80pq ; sécurité 128 bits)
    nonce : objet bytes de taille 16 (ne doit jamais être réutilisé avec la même clé)
    associateddata : objet bytes de longueur arbitraire
    plaintext : objet bytes de longueur arbitraire
    variant : "Ascon-128", "Ascon-128a" ou "Ascon-80pq"
              (détermine la taille de clé, le débit et le nombre de tours)
    retourne : un objet bytes de longueur len(plaintext)+16
               contenant le texte chiffré suivi du tag d’authentification
    """
    assert variant in ["Ascon-128", "Ascon-128a", "Ascon-80pq"]
    assert(len(nonce) == 16 and (len(key) == 16 or (len(key) == 20 and variant == "Ascon-80pq")))
    S = [0, 0, 0, 0, 0]
    k = len(key) * 8   # taille de clé en bits
    a = 12   # nombre de tours
    b = 8 if variant == "Ascon-128a" else 6   # nombre de tours
    rate = 16 if variant == "Ascon-128a" else 8   # débit en octets

    ascon_initialize(S, k, rate, a, b, key, nonce)
    ascon_process_associated_data(S, b, rate, associateddata)
    ciphertext = ascon_process_plaintext(S, b, rate, plaintext)
    tag = ascon_finalize(S, rate, a, key)
    return ciphertext + tag


def ascon_decrypt(key, nonce, associateddata, ciphertext, variant="Ascon-128"):
    """
    Fonction de déchiffrement Ascon.
    key : objet bytes de taille 16 (pour Ascon-128, Ascon-128a ; sécurité 128 bits)
          ou 20 (pour Ascon-80pq ; sécurité 128 bits)
    nonce : objet bytes de taille 16 (ne doit jamais être réutilisé avec la même clé)
    associateddata : objet bytes de longueur arbitraire
    ciphertext : objet bytes de longueur arbitraire (contient également le tag)
    variant : "Ascon-128", "Ascon-128a" ou "Ascon-80pq"
              (détermine la taille de clé, le débit et le nombre de tours)
    retourne : un objet bytes contenant le texte en clair,
               ou None si la vérification d’intégrité échoue
    """
    assert variant in ["Ascon-128", "Ascon-128a", "Ascon-80pq"]
    assert(len(nonce) == 16 and (len(key) == 16 or (len(key) == 20 and variant == "Ascon-80pq")))
    assert(len(ciphertext) >= 16)
    S = [0, 0, 0, 0, 0]
    k = len(key) * 8 # taille de clé en bits
    a = 12 # nombre de tours
    b = 8 if variant == "Ascon-128a" else 6   # nombre de tours intermédiaires
    rate = 16 if variant == "Ascon-128a" else 8   # débit en octets

    ascon_initialize(S, k, rate, a, b, key, nonce)
    ascon_process_associated_data(S, b, rate, associateddata)
    plaintext = ascon_process_ciphertext(S, b, rate, ciphertext[:-16])
    tag = ascon_finalize(S, rate, a, key)
    if tag == ciphertext[-16:]:
        return plaintext
    else:
        return None


# === Blocs internes de l’algorithme AEAD Ascon ===

def ascon_initialize(S, k, rate, a, b, key, nonce):
    """
    Phase d’initialisation d’Ascon - fonction utilitaire interne.
    S : état interne Ascon, liste de 5 entiers de 64 bits
    k : taille de la clé en bits
    rate : taille de bloc en octets (8 pour Ascon-128, Ascon-80pq ; 16 pour Ascon-128a)
    a : nombre de tours pour l’initialisation et la finalisation
    b : nombre de tours intermédiaires de permutation
    key : objet bytes de taille 16 (Ascon-128, Ascon-128a) ou 20 (Ascon-80pq)
    nonce : objet bytes de taille 16
    retourne : rien, met à jour l’état S
    """
    
    global debugtransformation
    
    iv_zero_key_nonce = to_bytes([k, rate * 8, a, b] + (20-len(key))*[0]) + key + nonce
    S[0], S[1], S[2], S[3], S[4] = bytes_to_state(iv_zero_key_nonce)
    if debug: printstate(S, "Valeur initiale    : ")

    debugtransformation = True
    ascon_permutation(S, a)
    debugtransformation = False
    
    zero_key = bytes_to_state(zero_bytes(40-len(key)) + key)
    S[0] ^= zero_key[0]
    S[1] ^= zero_key[1]
    S[2] ^= zero_key[2]
    S[3] ^= zero_key[3]
    S[4] ^= zero_key[4]
    if debugpermutation : myprintstate(S, "État ^ (0...0 & K) : ")

    if debug: printstate(S, "Initialisation     : ")

def ascon_process_associated_data(S, b, rate, associateddata):
    """
    Phase de traitement des données associées - fonction utilitaire interne.
    S : état interne Ascon, liste de 5 entiers de 64 bits
    b : nombre de tours intermédiaires de permutation
    rate : taille de bloc en octets (8 pour Ascon-128, 16 pour Ascon-128a)
    associateddata : objet bytes de longueur arbitraire
    retourne : rien, met à jour l’état S
    """
    if len(associateddata) > 0:
        a_zeros = rate - (len(associateddata) % rate) - 1
        a_padding = to_bytes([0x80] + [0 for i in range(a_zeros)])
        a_padded = associateddata + a_padding
        
        for block in range(0, len(a_padded), rate):
            S[0] ^= bytes_to_int(a_padded[block:block+8])
            if debugpermutation : myprintstate(S, "État ^ donnée A" + str(block+1) + "   : ")
            if rate == 16:
                S[1] ^= bytes_to_int(a_padded[block+8:block+16])

            ascon_permutation(S, b)

    S[4] ^= 1
    if debugpermutation : myprintstate(S, "État ^ (0...0 & 1) : ")
    if debug: printstate(S, "Donnée associée A  : ")
    

def ascon_process_plaintext(S, b, rate, plaintext):
    """
    Phase de traitement du texte clair (pendant le chiffrement) - fonction utilitaire interne.
    S : état interne Ascon, liste de 5 entiers de 64 bits
    b : nombre de tours intermédiaires de permutation
    rate : taille de bloc en octets (8 pour Ascon-128, Ascon-80pq ; 16 pour Ascon-128a)
    plaintext : objet bytes de longueur arbitraire
    retourne : le texte chiffré (sans le tag), met à jour l’état S
    """
    p_lastlen = len(plaintext) % rate
    p_padding = to_bytes([0x80] + (rate-p_lastlen-1)*[0x00])
    p_padded = plaintext + p_padding

    # Premiers blocs sauf le dernier
    ciphertext = to_bytes([])
    for block in range(0, len(p_padded) - rate, rate):
        if rate == 8:
            S[0] ^= bytes_to_int(p_padded[block:block+8])
            if debugpermutation : myprintstate(S, "État ^ Texte P" + str(int(block/rate)+1) + "    : ")
            ciphertext += int_to_bytes(S[0], 8)
            if debug: print("-- Texte chiffré C" + str(int(block/rate)+1) + " = 0x " + bytes_to_hex(int_to_bytes(S[0], 8)))
        elif rate == 16:
            S[0] ^= bytes_to_int(p_padded[block:block+8])
            S[1] ^= bytes_to_int(p_padded[block+8:block+16])
            ciphertext += (int_to_bytes(S[0], 8) + int_to_bytes(S[1], 8))
            
        ascon_permutation(S, b)

    # Dernier bloc
    block = len(p_padded) - rate
    if rate == 8:
        if debugpermutation : myprintstate(S, "État ^ Texte P" + str(int(block/rate)+1) + "    : ")
        S[0] ^= bytes_to_int(p_padded[block:block+8])
        ciphertext += int_to_bytes(S[0], 8)[:p_lastlen]
        if debug: print("-- Texte chiffré C" + str(int(block/rate)+1) + " = 0x " + bytes_to_hex(int_to_bytes(S[0], 8)[:p_lastlen]))
    elif rate == 16:
        S[0] ^= bytes_to_int(p_padded[block:block+8])
        S[1] ^= bytes_to_int(p_padded[block+8:block+16])
        ciphertext += (int_to_bytes(S[0], 8)[:min(8,p_lastlen)] + int_to_bytes(S[1], 8)[:max(0,p_lastlen-8)])
    if debug: printstate(S, "Texte clair P      : ")
    return ciphertext


def ascon_process_ciphertext(S, b, rate, ciphertext):
    """
    Phase de traitement du texte chiffré (pendant le déchiffrement) - fonction utilitaire interne.
    S : état interne Ascon, liste de 5 entiers de 64 bits
    b : nombre de tours intermédiaires de permutation
    rate : taille de bloc en octets (8 pour Ascon-128, Ascon-80pq ; 16 pour Ascon-128a)
    ciphertext : objet bytes de longueur arbitraire
    retourne : le texte en clair, met à jour l’état S
    """
    c_lastlen = len(ciphertext) % rate
    c_padded = ciphertext + zero_bytes(rate - c_lastlen)

    # Premiers blocs sauf le dernier
    plaintext = to_bytes([])
    for block in range(0, len(c_padded) - rate, rate):
        if rate == 8:
            Ci = bytes_to_int(c_padded[block:block+8])
            plaintext += int_to_bytes(S[0] ^ Ci, 8)
            S[0] = Ci
        elif rate == 16:
            Ci = (bytes_to_int(c_padded[block:block+8]), bytes_to_int(c_padded[block+8:block+16]))
            plaintext += (int_to_bytes(S[0] ^ Ci[0], 8) + int_to_bytes(S[1] ^ Ci[1], 8))
            S[0] = Ci[0]
            S[1] = Ci[1]

        ascon_permutation(S, b)

    # Dernier bloc
    block = len(c_padded) - rate
    if rate == 8:
        c_padding1 = (0x80 << (rate-c_lastlen-1)*8)
        c_mask = (0xFFFFFFFFFFFFFFFF >> (c_lastlen*8))
        Ci = bytes_to_int(c_padded[block:block+8])
        plaintext += int_to_bytes(Ci ^ S[0], 8)[:c_lastlen]
        S[0] = Ci ^ (S[0] & c_mask) ^ c_padding1
    elif rate == 16:
        c_lastlen_word = c_lastlen % 8
        c_padding1 = (0x80 << (8-c_lastlen_word-1)*8)
        c_mask = (0xFFFFFFFFFFFFFFFF >> (c_lastlen_word*8))
        Ci = (bytes_to_int(c_padded[block:block+8]), bytes_to_int(c_padded[block+8:block+16]))
        plaintext += (int_to_bytes(S[0] ^ Ci[0], 8) + int_to_bytes(S[1] ^ Ci[1], 8))[:c_lastlen]
        if c_lastlen < 8:
            S[0] = Ci[0] ^ (S[0] & c_mask) ^ c_padding1
        else:
            S[0] = Ci[0]
            S[1] = Ci[1] ^ (S[1] & c_mask) ^ c_padding1
    if debug: printstate(S, "process ciphertext:")
    return plaintext


def ascon_finalize(S, rate, a, key):
    """
    Phase de finalisation - fonction utilitaire interne.
    S : état interne Ascon, liste de 5 entiers de 64 bits
    rate : taille de bloc en octets (8 pour Ascon-128, Ascon-80pq ; 16 pour Ascon-128a)
    a : nombre de tours pour la permutation finale
    key : objet bytes de taille 16 (Ascon-128, Ascon-128a) ou 20 (Ascon-80pq)
    retourne : le tag d’authentification, met à jour l’état S
    """
    assert(len(key) in [16,20])
    S[rate//8+0] ^= bytes_to_int(key[0:8])
    S[rate//8+1] ^= bytes_to_int(key[8:16])
    S[rate//8+2] ^= bytes_to_int(key[16:])

    if debugpermutation : myprintstate(S, "État ^ (K & 0...0) : ")

    ascon_permutation(S, a)

    S[3] ^= bytes_to_int(key[-16:-8])
    S[4] ^= bytes_to_int(key[-8:])
    tag = int_to_bytes(S[3], 8) + int_to_bytes(S[4], 8)
    if debug: printstate(S, "Finalisation       : ")
    return tag


# === Permutation Ascon ===

def ascon_permutation(S, rounds=1):
    """
    Permutation centrale d’Ascon utilisée dans la construction éponge - fonction utilitaire interne.
    S : état interne Ascon, liste de 5 entiers de 64 bits
    rounds : nombre de tours à exécuter
    retourne : rien, met à jour l’état S
    """
    assert(rounds <= 12)
    for r in range(12-rounds, 12):
        # --- ajout des constantes de tour ---
        S[2] ^= (0xf0 - r*0x10 + r*0x1)
        if (debugtransformation or debugFull): 
            print("-- Permutation (r=" + "{:02d}".format(r) + ")")
            myprintstate(S, "Addition constante : ")
        # --- couche de substitution ---
        S[0] ^= S[4]
        S[4] ^= S[3]
        S[2] ^= S[1]
        T = [(S[i] ^ 0xFFFFFFFFFFFFFFFF) & S[(i+1)%5] for i in range(5)]
        for i in range(5):
            S[i] ^= T[(i+1)%5]
        S[1] ^= S[0]
        S[0] ^= S[4]
        S[3] ^= S[2]
        S[2] ^= 0XFFFFFFFFFFFFFFFF
        if (debugtransformation or debugFull): myprintstate(S, "Substitution S-box : ")
        # --- couche de diffusion linéaire ---
        S[0] ^= rotr(S[0], 19) ^ rotr(S[0], 28)
        S[1] ^= rotr(S[1], 61) ^ rotr(S[1], 39)
        S[2] ^= rotr(S[2],  1) ^ rotr(S[2],  6)
        S[3] ^= rotr(S[3], 10) ^ rotr(S[3], 17)
        S[4] ^= rotr(S[4],  7) ^ rotr(S[4], 41)
        if (debugtransformation or debugFull): myprintstate(S, "Diffusion linéaire : ")
        if (debugpermutation and not((debugtransformation or debugFull))): myprintstate(S, "Permutation (r=" + "{:02d}".format(r) + ") : ")
    

# === Fonctions utilitaires ===

def get_random_bytes(num):
    import os
    return to_bytes(os.urandom(num))

def zero_bytes(n):
    return n * b"\x00"

def to_bytes(l): # où l est une liste, un bytearray ou un objet bytes
    return bytes(bytearray(l))

def bytes_to_int(bytes):
    return sum([bi << ((len(bytes) - 1 - i)*8) for i, bi in enumerate(to_bytes(bytes))])

def bytes_to_state(bytes):
    return [bytes_to_int(bytes[8*w:8*(w+1)]) for w in range(5)]

def int_to_bytes(integer, nbytes):
    return to_bytes([(integer >> ((nbytes - 1 - i) * 8)) % 256 for i in range(nbytes)])

def rotr(val, r):
    return (val >> r) | ((val & (1<<r)-1) << (64-r))

def bytes_to_hex(b):
    # retourne une représentation hexadécimale formatée octet par octet
    return " ".join('{:02X}'.format(x) for x in b)
    
def printstate(S, description=""):
    print("*"*(16*5+5+20))
    print(description + " ".join(["{s:016x}".format(s=s) for s in S]))
    print("*"*(16*5+5+20))

def myprintstate(S, description=""):
    print(description + " ".join(["{s:016x}".format(s=s) for s in S]))
    
def printwords(S, description=""):
    print(" " + description)
    print("\n".join(["  x{i}={s:016x}".format(**locals()) for i, s in enumerate(S)]))


# === Quelques démonstrations si le fichier est exécuté directement ===

def demo_print(data):
    maxlen = max([len(text) for (text, val) in data])
    for text, val in data:
        print("{text}:{align} 0x{val} ({length} octets)".format(text=text, align=((maxlen - len(text)) * " "), val=bytes_to_hex(val), length=len(val)))

def demo_aead(variant):
    """
    Démonstration du chiffrement authentifié Ascon.
    """
    assert variant in ["Ascon-128", "Ascon-128a", "Ascon-80pq"]
    keysize = 20 if variant == "Ascon-80pq" else 16

    # Choisir une clé aléatoire cryptographiquement sûre
    # et un nonce jamais réutilisé avec la même clé :
    # key   = get_random_bytes(keysize)
    # nonce = get_random_bytes(16)
    
    # Nouvelle clé aléatoire (fixée ici pour la démonstration)
    key_hexa="8A55114D1CB6A9A2BE263D4D7AECAAFF"
    # Nouveau nonce aléatoire (fixé ici pour la démonstration)
    nonce_hexa="4ED0EC0B98C529B7C8CDDF37BCD0284A"
    # Nouveau message : une courbe de 121 octets normalisée avec des points entre 0 et 255
    plaintext_hexa="5A5B5B5A5A5A5A5A59554E4A4C4F545553515354565758575A5A595756595B5A5554545252504F4F4C4C4D4D4A49444447474644424341403B36383E4449494747464644434243454745444546474A494745484F58697C92AECEEDFFFFE3B47C471600041729363C3F3E40414141403F3F403F3E3B3A3B3E3D3E3C393C41464646454447464A4C4F4C505555524F5155595C5A595A5C5C5B5959575351504F4F53575A5C5A5B5D5E6060615F605F5E5A5857545252"
    
    key = bytes.fromhex(key_hexa)
    nonce = bytes.fromhex(nonce_hexa)
    plaintext= bytes.fromhex(plaintext_hexa)
    
    # associateddata = b"ASCON"
    # associateddata = bytes.fromhex(key_hexa)
    associateddata = b"A to B"

    # plaintext = b"RDV au Ti'bar ce soir ?"

    ciphertext = ascon_encrypt(key, nonce, associateddata, plaintext, variant)
    
    debug = True # False
    debugpermutation = True # False
    debugtransformation = True # False
    
    # receivedplaintext = ascon_decrypt(key, nonce, associateddata, ciphertext, variant)
    
    # if receivedplaintext == None: print("verification failed!")
        
    demo_print([("key", key), 
                ("nonce", nonce), 
                ("plaintext", plaintext), 
                ("ass.data", associateddata), 
                ("ciphertext", ciphertext[:-16]), 
                ("tag", ciphertext[-16:]), 
                #("received", receivedplaintext), 
               ])

def demo_hash(variant="Ascon-Hash", hashlength=32):
    """
    Démonstration de la fonction de hachage Ascon.
    """
    assert variant in ["Ascon-Xof", "Ascon-Hash", "Ascon-Xofa", "Ascon-Hasha"]
    print("=== démonstration du hachage avec {variant} ===".format(variant=variant))

    message = b"ascon"
    tag = ascon_hash(message, variant, hashlength)

    demo_print([("message", message), ("tag", tag)])


if __name__ == "__main__":
    demo_aead("Ascon-128")
    demo_hash("Ascon-Hash")