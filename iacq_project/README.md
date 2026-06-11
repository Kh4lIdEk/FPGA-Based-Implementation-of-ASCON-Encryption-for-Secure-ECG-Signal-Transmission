# Projet FPGA Sécurité — ASCON-128 sur FPGA PynqZ2 pour acquisition sécurisée de signaux ECG

## Nom du binôme
**Ali AHNANI & Khalid ELKOUSSAMI**

## Encadrants
- **Jean-Baptiste Rigaud**
- **Raphael Viera**

## Description du système
Ce projet a pour objectif de **sécuriser l’acquisition et la transmission de signaux ECG** en s’appuyant sur un **chiffrement ASCON-128** implémenté sur **FPGA PynqZ2**. Le système assure la **confidentialité** et l’**authenticité** des données biomédicales échangées entre un PC et la carte FPGA via une liaison **UART**.

Le fonctionnement général est le suivant :
1. un signal ECG est acquis côté PC ;
2. le PC envoie au FPGA la **clé**, le **nonce**, les **données associées** et la **trame ECG** ;
3. le FPGA exécute le chiffrement **ASCON-128 (AEAD)** ;
4. le texte chiffré et le tag sont renvoyés au PC ;
5. le PC réalise le **déchiffrement**, puis l’**analyse ECG** avec **NeuroKit2**.

Le système repose sur :
- une architecture matérielle `ascon_top` intégrant **UART**, **BRAM**, **ASCON-128** et plusieurs **machines d’états** ;
- une interface Python permettant de piloter les échanges UART avec le FPGA ;
- une chaîne logicielle de validation pour vérifier que **`decrypted == original`** et exploiter le signal ECG reconstruit.

## Organisation du projet Python
Le projet Python du binôme comprend notamment les fichiers suivants :
- `iacq.py` : interface de communication série avec le FPGA ;
- `ascon_pcsn.py` : déchiffrement logiciel de référence d’ASCON-128 ;
- `fpga_emulator.py` : émulateur pour les tests sans FPGA ;
- `visualization.py` : visualisation des signaux ;
- `main.py` : orchestration globale et analyse ECG.

## Fonction principale
Le système permet :
- d’envoyer une trame ECG vers le FPGA ;
- de chiffrer la trame avec **ASCON-128** ;
- de récupérer le **ciphertext** et le **tag** ;
- de déchiffrer et vérifier les données côté PC ;
- d’analyser le signal ECG restitué en temps réel.

## Prérequis
- Python 3
- `pyserial`
- `neurokit2`
- une carte **PynqZ2** programmée avec le design FPGA du projet, ou un mode d’émulation

Installation rapide :
```bash
pip install pyserial neurokit2
```

## Résultat attendu
À l’exécution, le projet doit permettre de démontrer qu’une trame ECG peut être :
- transmise,
- chiffrée sur FPGA,
- authentifiée,
- déchiffrée correctement,
- puis exploitée pour l’analyse biomédicale.

---
**École des Mines de Saint-Étienne — Institut Mines-Télécom**  
**Année 2025–2026**
