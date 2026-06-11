`timescale 1ns / 1ps

module fsm_ascon(
    input  logic       clock_i,
    input  logic       reset_i,
    input  logic       end_associate_i,
    input  logic       end_tag_i,
    input  logic       end_initialisation_i,
    input  logic       end_cipher_i,
    input  logic [4:0] counter_i,
    input  logic       start_i,
    output logic       init_o,
    output logic       associate_data_o,
    output logic       finalisation_o,
    output logic       data_valid_o,
    output logic       init_reg_o,
    output logic       en_reg_ascon_o, 
    output logic       en_cpt_o,
    output logic       init_cpt_o
);

typedef enum {                    
    START,
    INITIALISATION,
    END_INITIALISATION,
    ASSOCIATE_DATA,
    END_ASSOCIATE,         
    START_CIPHER,
    WAIT_CIPHER,
    CIPHER1,
    FINALISATION,
    END_FINALISATION,
    CIPHER3,
    DONE                         
} State_t;                         

State_t next_state, current_state; 

always_ff @(posedge clock_i or negedge reset_i) begin
    if (!reset_i) current_state <= START;
    else          current_state <= next_state; 
end
  
always_comb begin
    next_state = current_state; 
    unique case (current_state)
        START:
            if (start_i) next_state = INITIALISATION;
            
        INITIALISATION:
            next_state = END_INITIALISATION;
            
        END_INITIALISATION:
            if (end_initialisation_i) next_state = ASSOCIATE_DATA;
            
        ASSOCIATE_DATA:
            next_state = END_ASSOCIATE;
            
        END_ASSOCIATE:
            if (end_associate_i) next_state = START_CIPHER;
        
        // On traite 22 blocs normaux (index 1 à 22). Le 23ème bloc (index 23) déclenche la finalisation.
        START_CIPHER:
            if (counter_i < 5'd23) next_state = WAIT_CIPHER;
            else next_state = FINALISATION; 
        
        WAIT_CIPHER:
            if (end_cipher_i) next_state = CIPHER1;
            
        CIPHER1:
            next_state = START_CIPHER;
            
        FINALISATION:
            next_state = END_FINALISATION;
            
        END_FINALISATION:
            if (end_tag_i) next_state = CIPHER3; 
            
        CIPHER3:
            next_state = DONE;
            
        DONE:
            next_state = START;
        default:            next_state = START;
    endcase 
end
  
always_comb begin
    init_o              = 1'b0;
    associate_data_o    = 1'b0;
    data_valid_o        = 1'b0;
    finalisation_o      = 1'b0;
    init_reg_o          = 1'b0;
    en_reg_ascon_o      = 1'b0;
    en_cpt_o            = 1'b0;
    init_cpt_o          = 1'b0;

    unique case (current_state)
        START:
            init_cpt_o = 1'b1;
             
        INITIALISATION:
            begin init_o = 1'b1;
             init_reg_o = 1'b1;
             end
             
        END_INITIALISATION: ; 
        
        ASSOCIATE_DATA:
            begin associate_data_o = 1'b1;
             data_valid_o = 1'b1;
             end
        END_ASSOCIATE:
            if (end_associate_i) en_cpt_o = 1'b1; 
            
        START_CIPHER:
        if (counter_i < 5'd23) data_valid_o = 1'b1;
        
        WAIT_CIPHER: ; 
        
        // IMPULSION D'UN SEUL CYCLE POUR ÉCRIRE LE CIPHER EN RAM (Blocs 1 à 22)
        CIPHER1:
            begin en_reg_ascon_o = 1'b1;
            en_cpt_o = 1'b1;
            end
        
        FINALISATION:
            begin data_valid_o = 1'b1;
            finalisation_o = 1'b1;
            end
            
        END_FINALISATION: ; 
        
        // IMPULSION D'UN SEUL CYCLE POUR ÉCRIRE LE DERNIER BLOC (Bloc 23 / Padding)
        CIPHER3:
            en_reg_ascon_o = 1'b1; 
        
        DONE: ; 
        default: ;
    endcase
end
endmodule