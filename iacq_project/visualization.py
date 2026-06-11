"""
Module de visualisation des signaux ECG pour le projet IACQ.

Auteurs :
- AHNANI Ali <ahnaniali@gmail.com>
- Khalid ELKOUSSAMI <khalid.elkoussami@etu.emse.fr>

Date : 25/03/2026

Encadrants :
- Jean-Baptiste RIGAUD <jean-baptiste.rigaud@emse.fr>
- Olivier POTIN <olivier.potin@emse.fr>
- Raphael VIERA <raphael.viera@emse.fr>

Description :
Ce fichier contient les fonctions nécessaires à l’affichage et à l’analyse
visuelle des signaux ECG dans le projet IACQ. Il permet de tracer soit un
signal simple, soit une vue complète comparant le signal original, le signal
déchiffré et le signal chiffré. Il inclut également des outils d’analyse
cardiaque comme la détection des pics R, la délinéation PQRST, le calcul
de métriques HRV et l’identification d’éventuelles anomalies.
"""

import matplotlib
matplotlib.use('TkAgg')  # Utilise le moteur TkAgg pour l’affichage graphique
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
import pandas as pd
import numpy as np
import logging


def _safe_valid_peaks(peaks_series):
    """
    Convertit une série de pics d’onde
    (pouvant contenir des NaN, pd.NA ou None)
    en une liste propre d’indices entiers.
    """
    result = []
    for p in peaks_series:
        try:
            if p is None:
                continue
            f = float(p)
            if not np.isnan(f):
                result.append(int(f))
        except (TypeError, ValueError):
            continue
    return result


def compute_hrv_metrics(rpeaks, sampling_rate=360):
    """
    Calcule les métriques HRV à partir des indices des pics R :
    BPM, SDNN, RMSSD et pNN50.
    Retourne un dictionnaire, ou None si le nombre de pics est insuffisant.
    """
    if len(rpeaks) < 2:
        return None
    rr = np.diff(rpeaks) / sampling_rate * 1000  # intervalles RR en millisecondes
    bpm   = 60000 / np.mean(rr)
    sdnn  = np.std(rr, ddof=1)
    rmssd = np.sqrt(np.mean(np.diff(rr) ** 2))
    pnn50 = 100.0 * np.sum(np.abs(np.diff(rr)) > 50) / max(len(rr) - 1, 1)
    return dict(bpm=bpm, sdnn=sdnn, rmssd=rmssd, pnn50=pnn50, rr=rr)


def detect_anomalies(metrics):
    """
    Détecte d’éventuelles anomalies cardiaques à partir des métriques HRV.
    Retourne une liste de couples (étiquette, détail).
    """
    anomalies = []
    bpm   = metrics["bpm"]
    sdnn  = metrics["sdnn"]
    rmssd = metrics["rmssd"]
    pnn50 = metrics["pnn50"]
    rr    = metrics["rr"]

    if bpm < 50:
        anomalies.append(("⚠ Bradycardie", f"BPM={bpm:.1f} < 50"))
    elif bpm > 100:
        anomalies.append(("⚠ Tachycardie", f"BPM={bpm:.1f} > 100"))

    if sdnn < 20:
        anomalies.append(("⚠ HRV faible (SDNN)", f"SDNN={sdnn:.1f}ms < 20ms — possible dysfonction autonome"))
    elif sdnn > 100:
        anomalies.append(("⚠ HRV élevée (SDNN)", f"SDNN={sdnn:.1f}ms > 100ms — possible arythmie"))

    if rmssd > 50:
        anomalies.append(("⚠ RMSSD élevé", f"RMSSD={rmssd:.1f}ms > 50ms — rythme irrégulier"))

    if pnn50 > 50:
        anomalies.append(("⚠ pNN50 élevé", f"pNN50={pnn50:.1f}% > 50% — variabilité RR fréquente"))

    # Coefficient de variation des intervalles RR — permet de détecter un rythme irrégulier
    cv = np.std(rr) / np.mean(rr)
    if cv > 0.15:
        anomalies.append(("⚠ Rythme irrégulier", f"RR CV={cv:.2f} > 0.15 — possible arythmie"))

    return anomalies


def plot_ecg_data(data: pd.DataFrame, column: str = 'value',
                  title: str = 'Signal ECG normalisé', save_path: str = None):
    """
    Affiche les données ECG.

    Mode à trois panneaux (colonnes : original, plain, cipher) :
      - Panneau 1 : forme d’onde originale (vert)
      - Panneau 2 : ECG déchiffré avec délinéation PQRST + texte des métriques HRV
      - Panneau 3 : texte chiffré (rouge)
      - Panneau 4 : panneau des résultats d’analyse (tableau BPM/HRV + anomalies)

    Mode simple (toute autre colonne) :
      - affichage simple d’un seul signal
    """
    logger = logging.getLogger("IACQ_LOGGER")

    three_panel = (
        len(data.columns) >= 3
        and 'original' in data.columns
        and 'plain' in data.columns
        and 'cipher' in data.columns
    )

    if not three_panel and column not in data.columns:
        logger.error(f"Impossible d’afficher : la colonne '{column}' est absente du DataFrame.")
        return

    logger.info("Initialisation de l’affichage...")

    if three_panel:
        # ------------------------------------------------------------------ #
        #  Mise en page : 3 panneaux de signal + 1 panneau de texte d’analyse #
        # ------------------------------------------------------------------ #
        fig = plt.figure(figsize=(14, 14))
        gs = gridspec.GridSpec(4, 1, figure=fig,
                               height_ratios=[2, 2, 2, 1.2],
                               hspace=0.45)

        ax1 = fig.add_subplot(gs[0])
        ax2 = fig.add_subplot(gs[1])
        ax3 = fig.add_subplot(gs[2])
        ax4 = fig.add_subplot(gs[3])

        # --- Panneau 1 : signal original ---------------------------------- #
        ax1.plot(data['original'], color='g', linewidth=1.2)
        ax1.set_title('Forme d’onde originale', fontsize=13)
        ax1.set_ylabel('Amplitude', fontsize=11)
        ax1.grid(True, linestyle='--', alpha=0.6)

        # --- Panneau 2 : signal déchiffré avec PQRST ---------------------- #
        plain_values = data['plain'].values
        ax2.plot(plain_values, color='b', linewidth=1.2)
        title_plain = 'Signal ECG déchiffré'

        metrics = None
        anomalies = []

        try:
            import neurokit2 as nk

            sampling_rate = 360
            ecg_cleaned = nk.ecg_clean(plain_values, sampling_rate=sampling_rate)
            _, peaks_info = nk.ecg_peaks(ecg_cleaned, sampling_rate=sampling_rate)
            rpeaks = peaks_info["ECG_R_Peaks"]

            if len(rpeaks) > 1:
                # Pics R
                ax2.scatter(rpeaks, plain_values[rpeaks],
                            color='r', marker='o', zorder=5, s=60, label='R')

                # Délinéation PQRST
                _, waves = nk.ecg_delineate(ecg_cleaned, rpeaks,
                                             sampling_rate=sampling_rate,
                                             method="dwt")

                wave_styles = {
                    "ECG_P_Peaks": ('limegreen',   '^', 'P', 35),
                    "ECG_Q_Peaks": ('darkorange',  'v', 'Q', 35),
                    "ECG_S_Peaks": ('purple',      's', 'S', 30),
                    "ECG_T_Peaks": ('deeppink',    'D', 'T', 30),
                }
                for key, (color, marker, label, size) in wave_styles.items():
                    valid = _safe_valid_peaks(waves.get(key, []))
                    if valid:
                        valid = [p for p in valid if 0 <= p < len(plain_values)]
                        ax2.scatter(valid, plain_values[valid],
                                    color=color, marker=marker, zorder=5,
                                    s=size, label=label)

                ax2.legend(loc='lower left', fontsize='small', framealpha=0.8)

                # Métriques HRV
                metrics = compute_hrv_metrics(rpeaks, sampling_rate)
                if metrics:
                    anomalies = detect_anomalies(metrics)
                    title_plain += (
                        f"  |  BPM: {metrics['bpm']:.1f}"
                        f"  SDNN: {metrics['sdnn']:.1f}ms"
                        f"  RMSSD: {metrics['rmssd']:.1f}ms"
                        f"  pNN50: {metrics['pnn50']:.1f}%"
                    )

        except Exception as e:
            logger.warning(f"Erreur NeuroKit2 dans l’affichage final : {e}")

        ax2.set_title(title_plain, fontsize=12)
        ax2.set_ylabel('Amplitude', fontsize=11)
        ax2.grid(True, linestyle='--', alpha=0.6)

        # --- Panneau 3 : texte chiffré ------------------------------------ #
        ax3.plot(data['cipher'], color='salmon', linewidth=0.8)
        ax3.set_title('Texte chiffré (ASCON-128)', fontsize=13)
        ax3.set_xlabel('Indice de l’échantillon', fontsize=11)
        ax3.set_ylabel('Amplitude', fontsize=11)
        ax3.grid(True, linestyle='--', alpha=0.6)

        # --- Panneau 4 : résultats de l’analyse --------------------------- #
        ax4.axis('off')

        if metrics:
            # Construction du texte de rapport d’analyse
            status_color = 'red' if anomalies else 'green'
            status_label = '⚠  ANOMALIE DÉTECTÉE' if anomalies else '✓  Rythme sinusal normal'

            lines = [
                f"{'─' * 72}",
                f"  RAPPORT D’ANALYSE ECG",
                f"{'─' * 72}",
                f"  Fréquence cardiaque (BPM) : {metrics['bpm']:.1f} bpm",
                f"  SDNN                     : {metrics['sdnn']:.1f} ms   (normal : 20–100 ms)",
                f"  RMSSD                    : {metrics['rmssd']:.1f} ms   (normal : 15–40 ms)",
                f"  pNN50                    : {metrics['pnn50']:.1f} %    (normal : 3–45 %)",
                f"{'─' * 72}",
                f"  Statut                   : {status_label}",
            ]
            if anomalies:
                for label, detail in anomalies:
                    lines.append(f"    {label}  —  {detail}")
            lines.append(f"{'─' * 72}")

            report_text = '\n'.join(lines)
            ax4.text(0.01, 0.98, report_text,
                     transform=ax4.transAxes,
                     verticalalignment='top',
                     fontsize=9.5,
                     fontfamily='monospace',
                     color=status_color,
                     bbox=dict(boxstyle='round,pad=0.5',
                               facecolor='#f8f8f8',
                               edgecolor=status_color,
                               linewidth=1.5))
        else:
            ax4.text(0.5, 0.5,
                     'Signal insuffisant pour l’analyse HRV\n'
                     '(au moins 2 pics R nécessaires)',
                     transform=ax4.transAxes,
                     ha='center', va='center',
                     fontsize=11, color='gray')

        fig.suptitle(title, fontsize=15, fontweight='bold')

    else:
        # ------------------------------------------------------------------ #
        #  Affichage simple d’une seule colonne                              #
        # ------------------------------------------------------------------ #
        fig, ax = plt.subplots(figsize=(12, 5))
        ax.plot(data[column], color='b', linewidth=1.5)
        ax.set_title(title, fontsize=14)
        ax.set_xlabel('Indice de l’échantillon', fontsize=12)
        ax.set_ylabel('Amplitude (normalisée)', fontsize=12)
        ax.grid(True, linestyle='--', alpha=0.7)
        plt.tight_layout()

    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches='tight')
        logger.info(f"Graphique enregistré dans {save_path}")

    plt.show()