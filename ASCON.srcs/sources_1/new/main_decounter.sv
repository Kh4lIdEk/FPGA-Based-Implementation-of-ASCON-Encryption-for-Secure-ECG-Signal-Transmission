`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module   : main_decounter
// Desc     : Décompteur paramétrable selon la phase ASCON active
//            Valeurs de chargement :
//              - Key/Nonce : 16 octets
//              - Associated Data : 8 octets
//              - Wave : 184 octets
//              - Cipher : 185 octets (184 + 1 "OK")
//              - Tag : 17 octets  (16  + 1 "OK")
//////////////////////////////////////////////////////////////////////////////////

module main_decounter
  import uart_pkg::*;
(
    input  logic        clock_i,
    input  logic        resetb_i,       // Reset asynchrone actif bas

    input  logic        en_i,           // Active le décomptage / le chargement

    // Signaux de chargement (priorité décroissante)
    input  logic        init_cpt_key_nonce_16_i,  // Charge 16  (key/nonce)
    input  logic        init_cpt_ad_8_i,          // Charge 8   (associated data)

    output logic [8:0]  data_o          // Valeur courante du décompteur
);

    // -------------------------------------------------------------------------
    // Registre du décompteur
    // -------------------------------------------------------------------------
    always_ff @(posedge clock_i or negedge resetb_i) begin
        if (!resetb_i) begin
            data_o <= '0;
        end else if (en_i) begin
            if      (init_cpt_key_nonce_16_i)           data_o <= 9'd16;
            else if (init_cpt_ad_8_i)                   data_o <= 9'd8;
            else                                        data_o <= data_o - 1'b1;
        end
    end

endmodule : main_decounter