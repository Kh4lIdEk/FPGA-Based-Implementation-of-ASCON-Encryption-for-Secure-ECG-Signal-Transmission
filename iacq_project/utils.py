"""
Outils de journalisation pour le projet IACQ.

Auteurs :
- AHNANI Ali <ahnaniali@gmail.com>
- Khalid ELKOUSSAMI <khalid.elkoussami@etu.emse.fr>

Date : 25/03/2026

Encadrants :
- Jean-Baptiste RIGAUD <jean-baptiste.rigaud@emse.fr>
- Olivier POTIN <olivier.potin@emse.fr>
- Raphael VIERA <raphael.viera@emse.fr>

Description :
Ce fichier contient une fonction utilitaire permettant de configurer
un système de journalisation pour le projet IACQ. Le journal est écrit
à la fois dans un fichier de log et dans la console, afin de faciliter
le suivi de l’exécution, le débogage et l’analyse des communications
avec le FPGA ou son émulateur.
"""

import logging
import os

def setup_logger(log_file: str = "logs/fpga_comm.log"):
    """
    Configure un journal d’exécution qui écrit à la fois
    dans un fichier et dans la console.
    """
    # Crée automatiquement le dossier parent du fichier de log s’il n’existe pas
    os.makedirs(os.path.dirname(log_file), exist_ok=True)

    # Récupère ou crée le logger principal du projet
    logger = logging.getLogger("IACQ_LOGGER")
    logger.setLevel(logging.DEBUG)
    
    # Évite d’ajouter plusieurs fois les mêmes handlers
    # lorsque le script est relancé plusieurs fois
    if not logger.handlers:
        # Handler pour l’écriture dans le fichier de log
        fh = logging.FileHandler(log_file)
        fh.setLevel(logging.DEBUG)
        
        # Handler pour l’affichage dans la console
        ch = logging.StreamHandler()
        ch.setLevel(logging.INFO)
        
        # Format commun des messages de log
        formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        fh.setFormatter(formatter)
        ch.setFormatter(formatter)
        
        # Association des handlers au logger
        logger.addHandler(fh)
        logger.addHandler(ch)
        
    return logger