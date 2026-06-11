"""
main.py — Exécution du protocole IACQ sur le FPGA réel via UART.

Auteurs :
- AHNANI Ali <ahnaniali@gmail.com>
- Khalid ELKOUSSAMI <khalid.elkoussami@etu.emse.fr>

Date : 25/03/2026

Encadrants :
- Jean-Baptiste RIGAUD <jean-baptiste.rigaud@emse.fr>
- Olivier POTIN <olivier.potin@emse.fr>
- Raphael VIERA <raphael.viera@emse.fr>

Description :
Ce fichier constitue le point d’entrée principal pour exécuter le protocole
IACQ avec un FPGA réel connecté en UART. Il permet de charger des trames ECG
depuis un fichier CSV, d’envoyer les paramètres ASCON-128 au FPGA, de lancer
le chiffrement matériel, de récupérer les données chiffrées et le tag, puis
de déchiffrer côté PC afin de vérifier l’intégrité de la chaîne complète.
Le script peut également afficher une visualisation temps réel et finale des
signaux originaux, chiffrés et déchiffrés.

Utilisation :
    python main.py                         # port COM8 par défaut
    python main.py --port COM3             # port personnalisé
    python main.py --no-plot               # désactive la visualisation ECG
"""

import os
import sys
import argparse
import time

# Force la sortie UTF-8 sous Windows pour éviter les erreurs d’encodage cp1252
if sys.platform == "win32":
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from iacq import IACQ, high_pass_filter, low_pass_filter
from utils import setup_logger
from visualization import plot_ecg_data
import neurokit2 as nk
import numpy as np

# ---------------------------------------------------------------------------
# Configuration matérielle
# ---------------------------------------------------------------------------
HARDWARE_PORT = "COM4"
BAUD_RATE     = 115200
UART_TIMEOUT  = 2       # délai maximal de lecture pyserial en secondes

# ---------------------------------------------------------------------------
# Paramètres ASCON-128 — doivent correspondre au firmware du FPGA
# ---------------------------------------------------------------------------
KEY   = bytes.fromhex("8A55114D1CB6A9A2BE263D4D7AECAAFF")
NONCE = bytes.fromhex("4ED0EC0B98C529B7C8CDDF37BCD0284A")

# Données associées sur 8 octets complétés, envoyées au FPGA via UART
ASSOCIATED_DATA_FPGA    = bytes.fromhex("4120746F20428000")  # b"A to B" + 0x80 0x00

# Données associées brutes passées à ascon_decrypt — la bibliothèque ajoute le bourrage en interne
ASSOCIATED_DATA_DECRYPT = bytes.fromhex("4120746F2042")


# ---------------------------------------------------------------------------
# Chargeur de trames
# ---------------------------------------------------------------------------

def load_trames(filepath: str) -> list:
    """
    Charge des trames de forme d’onde de 181 octets depuis un fichier CSV.
    Chaque ligne doit contenir une chaîne hexadécimale
    (par exemple 362 caractères hexadécimaux pour 181 octets).
    Les lignes qui ne font pas exactement 181 octets sont ignorées avec un avertissement.
    """
    import csv
    trames = []
    with open(filepath, newline='', encoding='utf-8') as f:
        for lineno, row in enumerate(csv.reader(f), start=1):
            if not row:
                continue
            hex_str = ''.join(row).replace(' ', '')
            try:
                trame = bytes.fromhex(hex_str)
            except ValueError as e:
                print(f"[WARN] line {lineno}: cannot parse — {e}")
                continue
            if len(trame) != 181:
                print(f"[WARN] line {lineno}: skipping trame of {len(trame)} bytes (expected 181)")
                continue
            trames.append(trame)
    return trames


# ---------------------------------------------------------------------------
# Fonction principale
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Chiffrement ASCON-128 sur FPGA via UART, déchiffrement sur PC."
    )
    parser.add_argument("--port",       default=HARDWARE_PORT,
                        help=f"Port série (par défaut : {HARDWARE_PORT})")
    parser.add_argument("--baud",       type=int, default=BAUD_RATE,
                        help=f"Débit en bauds (par défaut : {BAUD_RATE})")
    parser.add_argument("--timeout",    type=float, default=UART_TIMEOUT,
                        help=f"Délai maximal de lecture série en secondes (par défaut : {UART_TIMEOUT})")
    parser.add_argument("--emulator",   action="store_true",
                        help="Utilise FPGAEmulator à la place du matériel réel (pour les tests à domicile)")
    parser.add_argument("--trame-file", default="data/xNorm.csv",
                        help="Fichier CSV contenant des trames hexadécimales de 181 octets")
    parser.add_argument("--ecg-file",   default="data/xNorm.csv",
                        help="Fichier CSV pour la visualisation ECG")
    parser.add_argument("--no-plot",    action="store_true",
                        help="Désactive la visualisation ECG")
    args = parser.parse_args()

    # Journalisation
    os.makedirs("logs", exist_ok=True)
    logger = setup_logger("logs/fpga_comm.log")
    mode = "EMULATOR" if args.emulator else f"hardware port={args.port}"
    logger.info(f"IACQ mode={mode}, baud={args.baud}, timeout={args.timeout}s")

    # Chargement des trames
    if not os.path.exists(args.trame_file):
        logger.critical(f"Trame file not found: {args.trame_file}")
        sys.exit(1)

    trames = load_trames(args.trame_file)
    if not trames:
        logger.critical("No valid 181-byte trames found. Aborting.")
        sys.exit(1)

    logger.info(f"Loaded {len(trames)} trame(s) from '{args.trame_file}'.")

    # Connexion FPGA
    iacq = IACQ(port=args.port, baud_rate=args.baud,
                timeout=args.timeout, emulator=args.emulator)

    results = []

    try:
        iacq.open()
        logger.info(f"Serial port {args.port} opened.")

        if not args.no_plot:
            logger.info("Initializing live plot...")
            import matplotlib.pyplot as plt
            from collections import deque
            
            plt.ion()
            fig, (ax1, ax2, ax3) = plt.subplots(3, 1, figsize=(10, 10))
            
            line1, = ax1.plot([], [], color='g')
            ax1.set_title("Live Original Waveform")
            ax1.set_ylabel("Amplitude")
            ax1.grid(True, linestyle='--', alpha=0.7)

            line2, = ax2.plot([], [], color='b')
            scatter_rpeaks = ax2.scatter([], [], color='r', marker='o', zorder=5, s=50, label='R')
            scatter_ppeaks = ax2.scatter([], [], color='g', marker='^', zorder=5, s=30, label='P')
            scatter_qpeaks = ax2.scatter([], [], color='orange', marker='v', zorder=5, s=30, label='Q')
            scatter_speaks = ax2.scatter([], [], color='purple', marker='^', zorder=5, s=30, label='S')
            scatter_tpeaks = ax2.scatter([], [], color='magenta', marker='o', zorder=5, s=40, label='T')
            ax2.legend(loc='lower left', fontsize='small')
            text_metrics = ax2.text(0.01, 0.95, 'Waiting for data...', transform=ax2.transAxes, 
                                    verticalalignment='top', fontsize=10,
                                    bbox=dict(boxstyle='round', facecolor='white', alpha=0.8))
            ax2.set_title("Live Decrypted ECG Waveform")
            ax2.set_ylabel("Amplitude")
            ax2.grid(True, linestyle='--', alpha=0.7)
            
            line3, = ax3.plot([], [], color='r')
            ax3.set_title("Live Encrypted Ciphertext")
            ax3.set_xlabel("Samples")
            ax3.set_ylabel("Amplitude")
            ax3.grid(True, linestyle='--', alpha=0.7)
            
            plt.tight_layout()
            plt.show(block=False)
            
            buffer_original = deque(maxlen=1800)
            buffer_plain = deque(maxlen=1800)  # 5 secondes à 360 Hz
            buffer_cipher = deque(maxlen=1800)

        # Mesures de performance
        start_time = time.time()
        encryption_times = []
        error_count = 0
        success_count = 0

        for i, trame in enumerate(trames):
            logger.info("=" * 60)
            logger.info(f"Trame {i+1}/{len(trames)} — encrypting on FPGA...")

            cycle_start = time.time()

            try:
                # Étape 1 — le FPGA chiffre (données associées complétées sur 8 octets)
                ciphertext, tag = iacq.encrypt_on_fpga(
                    waveform=trame,
                    key=KEY,
                    nonce=NONCE,
                    associated_data=ASSOCIATED_DATA_FPGA,
                )
                logger.info(f"[FPGA -> PC] tag       : {tag.hex()}")
                logger.info(f"[FPGA -> PC] ciphertext: {len(ciphertext)} bytes | {ciphertext[:16].hex()}...")

                # Étape 2 — le PC déchiffre (données associées brutes — ascon_decrypt ajoute le bourrage en interne)
                logger.info("Decrypting on PC with Python ASCON reference...")
                decrypted = iacq.decrypt_waveform(
                    ciphertext=ciphertext,
                    tag=tag,
                    key=KEY,
                    nonce=NONCE,
                    associated_data=ASSOCIATED_DATA_DECRYPT,
                )

                cycle_end = time.time()
                cycle_time = cycle_end - cycle_start
                encryption_times.append(cycle_time)
                logger.info(f"Cycle time: {cycle_time:.4f} seconds")

                # Étape 3 — validation
                if decrypted == trame:
                    logger.info(f"[OK] VALIDATION PASSED — decrypted == original waveform ({len(decrypted)} bytes)")
                    results.append((i, True, ciphertext, tag, decrypted))
                    success_count += 1
                else:
                    first_diff = next(
                        (j for j, (a, b) in enumerate(zip(decrypted, trame)) if a != b), "?"
                    )
                    logger.error(
                        f"[FAIL] VALIDATION FAILED — "
                        f"decrypted {len(decrypted)} bytes vs original {len(trame)} bytes | "
                        f"first diff at byte {first_diff}"
                    )
                    results.append((i, False, ciphertext, tag, decrypted))
                    error_count += 1
                
                # Mise à jour de l’affichage en direct
                if not args.no_plot:
                    try:
                        trame_avant_int = np.frombuffer(trame, dtype=np.uint8).astype(np.float64)
                        decrypted_trame_int = np.frombuffer(decrypted, dtype=np.uint8).astype(np.float64)
                        cipher_int = np.frombuffer(ciphertext[:len(decrypted)], dtype=np.uint8).astype(np.float64)
                        
                        # Normalisation du signal (centrage autour de zéro)
                        trame_avant_int -= np.mean(trame_avant_int)
                        decrypted_trame_int -= np.mean(decrypted_trame_int)
                        cipher_int -= np.mean(cipher_int)

                        # Application des filtres
                        trame_avant_filtered = low_pass_filter(high_pass_filter(trame_avant_int))
                        trame_apres_filtered = low_pass_filter(high_pass_filter(decrypted_trame_int))
                    except Exception:
                        trame_avant_filtered = list(trame)
                        trame_apres_filtered = list(decrypted)
                        cipher_int = list(ciphertext)[:len(decrypted)]

                    buffer_original.extend(trame_avant_filtered)
                    buffer_plain.extend(trame_apres_filtered)
                    buffer_cipher.extend(cipher_int)
                    
                    line1.set_data(range(len(buffer_original)), list(buffer_original))
                    ax1.relim()
                    ax1.autoscale_view()
                    
                    line2.set_data(range(len(buffer_plain)), list(buffer_plain))
                    
                    # Analyse temps réel avec NeuroKit2
                    if len(buffer_plain) > 360:  # besoin de contexte pour les pics (au moins 1 seconde)
                        try:
                            # Nettoyage du signal
                            ecg_signal = np.array(buffer_plain)
                            ecg_cleaned = nk.ecg_clean(ecg_signal, sampling_rate=360)
                            
                            # Détection des pics R
                            _, peaks_info = nk.ecg_peaks(ecg_cleaned, sampling_rate=360)
                            rpeaks = peaks_info["ECG_R_Peaks"]
                            
                            if len(rpeaks) > 1:
                                scatter_rpeaks.set_offsets(np.c_[rpeaks, ecg_signal[rpeaks]])
                                
                                # Délinéation PQRST
                                _, waves = nk.ecg_delineate(ecg_cleaned, rpeaks, sampling_rate=360, method="dwt")
                                
                                def update_wave_scatter(scatter_obj, wave_key):
                                    peaks = waves.get(wave_key, [])
                                    valid_peaks = []
                                    for p in peaks:
                                        try:
                                            f = float(p)
                                            if not np.isnan(f):
                                                valid_peaks.append(int(f))
                                        except (TypeError, ValueError):
                                            continue
                                    valid_peaks = [p for p in valid_peaks if 0 <= p < len(ecg_signal)]
                                    if valid_peaks:
                                        scatter_obj.set_offsets(np.c_[valid_peaks, ecg_signal[valid_peaks]])
                                    else:
                                        scatter_obj.set_offsets(np.empty((0, 2)))

                                update_wave_scatter(scatter_ppeaks, "ECG_P_Peaks")
                                update_wave_scatter(scatter_qpeaks, "ECG_Q_Peaks")
                                update_wave_scatter(scatter_speaks, "ECG_S_Peaks")
                                update_wave_scatter(scatter_tpeaks, "ECG_T_Peaks")

                                rr_intervals = np.diff(rpeaks) / 360 * 1000  # en millisecondes
                                
                                bpm = 60000 / np.mean(rr_intervals)
                                sdnn = np.std(rr_intervals)
                                rmssd = np.sqrt(np.mean(np.diff(rr_intervals)**2))
                                pnn50 = (100 * np.sum(np.abs(np.diff(rr_intervals)) > 50) / max(len(rr_intervals) - 1, 1)) if len(rr_intervals) > 1 else 0.0
                                
                                anomalies = []
                                if bpm < 50:
                                    anomalies.append("Bradycardia")
                                elif bpm > 100:
                                    anomalies.append("Tachycardia")
                                if sdnn < 20:
                                    anomalies.append("Low HRV(SDNN)")
                                elif sdnn > 100:
                                    anomalies.append("High HRV(SDNN)")
                                if rmssd > 50:
                                    anomalies.append("High RMSSD")
                                if pnn50 > 50:
                                    anomalies.append("High pNN50")
                                cv = np.std(rr_intervals) / np.mean(rr_intervals) if np.mean(rr_intervals) > 0 else 0
                                if cv > 0.15:
                                    anomalies.append("Irregular Rhythm")

                                if anomalies:
                                    prefix = "⚠ " + " | ".join(anomalies) + "  "
                                    text_metrics.set_color('red')
                                else:
                                    prefix = "✓ Normal  "
                                    text_metrics.set_color('darkgreen')

                                stats = (f"{prefix}BPM: {bpm:.1f} | SDNN: {sdnn:.1f}ms"
                                         f" | RMSSD: {rmssd:.1f}ms | pNN50: {pnn50:.1f}%")
                                text_metrics.set_text(stats)
                            else:
                                scatter_rpeaks.set_offsets(np.empty((0, 2)))
                                scatter_ppeaks.set_offsets(np.empty((0, 2)))
                                scatter_qpeaks.set_offsets(np.empty((0, 2)))
                                scatter_speaks.set_offsets(np.empty((0, 2)))
                                scatter_tpeaks.set_offsets(np.empty((0, 2)))
                                text_metrics.set_text("Analyzing...")
                        except Exception as e:
                            logger.error(f"NeuroKit2 Error: {e}")
                    else:
                        scatter_rpeaks.set_offsets(np.empty((0, 2)))
                        scatter_ppeaks.set_offsets(np.empty((0, 2)))
                        scatter_qpeaks.set_offsets(np.empty((0, 2)))
                        scatter_speaks.set_offsets(np.empty((0, 2)))
                        scatter_tpeaks.set_offsets(np.empty((0, 2)))
                        text_metrics.set_text("Buffering signal...")
                    ax2.relim()
                    ax2.autoscale_view()
                    
                    line3.set_data(range(len(buffer_cipher)), list(buffer_cipher))
                    ax3.relim()
                    ax3.autoscale_view()
                    
                    fig.canvas.draw()
                    fig.canvas.flush_events()
                    plt.pause(0.01)  # petite pause pour permettre la mise à jour de l’affichage

            except Exception as e:
                cycle_end = time.time()
                cycle_time = cycle_end - cycle_start
                encryption_times.append(cycle_time)
                logger.error(f"[ERROR] Cycle {i+1} failed: {e}")
                results.append((i, False, b'', b'', b''))
                error_count += 1

        total_time = time.time() - start_time

    except KeyboardInterrupt:
        logger.warning("Interrupted by user.")
    except Exception as e:
        logger.critical(f"FATAL ERROR: {e}", exc_info=True)
    finally:
        iacq.close()
        logger.info("Serial port closed.")

    # Résumé
    passed = sum(1 for r in results if r[1])
    logger.info("=" * 60)
    logger.info("--- PERFORMANCE METRICS ---")
    if 'encryption_times' in locals() and encryption_times:
        avg_time = sum(encryption_times) / len(encryption_times)
        max_time = max(encryption_times)
        min_time = min(encryption_times)
        logger.info(f"Time per cycle (avg): {avg_time:.4f} s")
        logger.info(f"Time per cycle (min): {min_time:.4f} s")
        logger.info(f"Time per cycle (max): {max_time:.4f} s")
    else:
        logger.info("Time per cycle      : N/A")

    if 'total_time' in locals() and 'trames' in locals():
        throughput = len(trames) / total_time if total_time > 0 else 0
        logger.info(f"Total time          : {total_time:.4f} s")
        logger.info(f"Total throughput    : {throughput:.2f} waveforms/s")
    
    if 'error_count' in locals():
        logger.info(f"Errors / Dropped    : {error_count}")
        
    logger.info("============================================================")
    logger.info(f"Summary: {passed}/{len(results)} trame(s) passed end-to-end validation.")

    # Visualisation ECG finale à partir des seules données déchiffrées valides
    if not args.no_plot and success_count > 0:
        try:
            print("Displaying final ECG visualisation of decrypted data (close window to exit)...")
            import pandas as pd
            # Création d’un DataFrame à partir des données mises en mémoire
            # ou reconstruction à partir des résultats
            # Recherche de toutes les trames correctement déchiffrées
            successful_results = [(r[0], r[1], r[2], r[3], r[4], trames[r[0]]) for r in results if r[1]]
            all_original = []
            all_plain = []
            all_cipher = []
            
            for r in successful_results:
                try:
                    trame_avant_int = np.frombuffer(r[5], dtype=np.uint8).astype(np.float64)
                    decrypted_trame_int = np.frombuffer(r[4], dtype=np.uint8).astype(np.float64)
                    cipher_int = np.frombuffer(r[2][:len(r[4])], dtype=np.uint8).astype(np.float64)
                    
                    # Normalisation
                    trame_avant_int -= np.mean(trame_avant_int)
                    decrypted_trame_int -= np.mean(decrypted_trame_int)
                    cipher_int -= np.mean(cipher_int)
                    
                    # Filtrage
                    trame_avant_filtered = low_pass_filter(high_pass_filter(trame_avant_int))
                    trame_apres_filtered = low_pass_filter(high_pass_filter(decrypted_trame_int))
                    
                    all_original.extend(list(trame_avant_filtered))
                    all_plain.extend(list(trame_apres_filtered))
                    all_cipher.extend(list(cipher_int))
                except Exception:
                    all_original.extend(list(r[5]))
                    all_plain.extend(list(r[4]))
                    all_cipher.extend(list(r[2])[:len(r[4])])
                
            data_df = pd.DataFrame({'original': all_original, 'plain': all_plain, 'cipher': all_cipher})
            plot_ecg_data(data_df, title="End-to-End Original vs Plain vs Encrypted Signal")
        except Exception as e:
            logger.warning(f"Could not display final ECG plot: {e}")

if __name__ == "__main__":
    main()