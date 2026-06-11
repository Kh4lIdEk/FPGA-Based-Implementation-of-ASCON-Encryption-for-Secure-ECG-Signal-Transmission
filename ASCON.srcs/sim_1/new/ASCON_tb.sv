`timescale 1ns / 1ps
module ascon_tb();
    // inputs   
    logic         clock_s;
    logic         reset_s;
    logic         init_s;
    logic         associate_data_s;
    logic         finalisation_s;
    logic [ 63:0] data_s;
    logic         data_valid_s;
    logic [127:0] key_s;
    logic [127:0] nonce_s;
    
    // outputs
    logic         end_associate_s;
    logic [ 63:0] cipher_s;
    logic         cipher_valid_s;
    logic [127:0] tag_s;
    logic         end_tag_s;
    logic         end_initialisation_s;
    logic         end_cipher_s;

    logic [1471:0] data_i_s;
    
    assign data_i_s = 1472'h5A_5B_5B_5A_5A_5A_5A_5A_59_55_4E_4A_4C_4F_54_55_53_51_53_54_56_57_58_57_5A_5A_59_57_56_59_5B_5A_55_54_54_52_52_50_4F_4F_4C_4C_4D_4D_4A_49_44_44_47_47_46_44_42_43_41_40_3B_36_38_3E_44_49_49_47_47_46_46_44_43_42_43_45_47_45_44_45_46_47_4A_49_47_45_48_4F_58_69_7C_92_AE_CE_ED_FF_FF_E3_B4_7C_47_16_00_04_17_29_36_3C_3F_3E_40_41_41_41_40_3F_3F_40_3F_3E_3B_3A_3B_3E_3D_3E_3C_39_3C_41_46_46_46_45_44_47_46_4A_4C_4F_4C_50_55_55_52_4F_51_55_59_5C_5A_59_5A_5C_5C_5B_59_59_57_53_51_50_4F_4F_53_57_5A_5C_5A_5B_5D_5E_60_60_61_5F_60_5F_5E_5A_58_57_54_52_52_80_00_00;
    
    assign key_s = 128'h8A_55_11_4D_1C_B6_A9_A2_BE_26_3D_4D_7A_EC_AA_FF;
    assign nonce_s = 128'h4E_D0_EC_0B_98_C5_29_B7_C8_CD_DF_37_BC_D0_28_4A;

    ascon DUT(
        .clock_i(clock_s),
        .reset_i(reset_s),
        .init_i(init_s),
        .associate_data_i(associate_data_s),
        .finalisation_i(finalisation_s),
        .data_i(data_s),
        .data_valid_i(data_valid_s),
        .key_i(key_s),
        .nonce_i(nonce_s),
        .end_associate_o(end_associate_s),
        .cipher_o(cipher_s),
        .cipher_valid_o(cipher_valid_s),
        .tag_o(tag_s),
        .end_tag_o(end_tag_s),
        .end_initialisation_o(end_initialisation_s),
        .end_cipher_o(end_cipher_s)    
    );

    // ===========================================================================
    // Génération de l'horloge (100 MHz)
    // ===========================================================================
    initial begin
        clock_s = 1'b0;
        forever #5 clock_s = ~clock_s; // Période 10ns
    end

    // ===========================================================================
    // Scénario de Test Synchrone
    // ===========================================================================
    initial begin
        $display("===== DEBUT TEST COEUR ASCON =====");

        // 1. État initial et Reset
        reset_s          = 1'b1;
        init_s           = 1'b0;
        associate_data_s = 1'b0; 
        finalisation_s   = 1'b0;
        data_s           = 64'h0;
        data_valid_s     = 1'b0;
        
        // Attente propre de quelques cycles d'horloge
        repeat(5) @(negedge clock_s);
        reset_s = 1'b0;
        repeat(5) @(negedge clock_s);

        // 2. Initialisation
        init_s = 1'b1;
        @(negedge clock_s);
        init_s = 1'b0;
        
        wait(end_initialisation_s == 1'b1);
        @(negedge clock_s);

        // 3. Données Associées (AD)
        associate_data_s = 1'b1;
        data_valid_s     = 1'b1;
        data_s           = 64'h41_20_74_6F_20_42_80_00;
        @(negedge clock_s);
        associate_data_s = 1'b0;
        data_valid_s     = 1'b0;
        
        wait(end_associate_s == 1'b1);
        @(negedge clock_s);

        // 4. Plaintext (Boucle sur les 22 premiers blocs)
        for (int i=1; i<23; i++) begin
            data_s       = data_i_s[1472 - 64*i +: 64];
            data_valid_s = 1'b1;
            @(negedge clock_s);
            data_valid_s = 1'b0;
            
            // On attend que le cipher soit prêt
            wait(cipher_valid_s == 1'b1);
            $display("cipher[%0d] = %h", i, cipher_s);
            
            // On attend que l'ASCON annonce la fin du traitement du bloc
            wait(end_cipher_s == 1'b1);
            @(negedge clock_s);
        end

        // 5. Finalisation (Le 23ème bloc avec padding)
        finalisation_s = 1'b1;
        data_valid_s   = 1'b1;
        data_s         = data_i_s[63:0];
        @(negedge clock_s);
        finalisation_s = 1'b0;
        data_valid_s   = 1'b0;

        // Attente du dernier bloc de Cipher
        wait(cipher_valid_s == 1'b1);
        $display("cipher[23] = %h", cipher_s);

        // 6. Attente et lecture du Tag
        wait(end_tag_s == 1'b1);
        @(negedge clock_s);
        $display("tag = %h", tag_s);

        // Fin du test
        $display("===== FIN TEST COEUR ASCON =====");
        $finish;
    end

endmodule