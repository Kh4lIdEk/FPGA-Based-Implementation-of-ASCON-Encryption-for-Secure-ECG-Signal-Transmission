class IACQError(Exception):
    """Exception de base pour toutes les erreurs liées à IACQ."""
    pass

class FPGAError(Exception):
    """Exception de base pour toutes les erreurs liées au FPGA."""
    pass

class FPGAConnectionError(FPGAError):
    """La connexion ne peut pas être établie ou a été perdue."""
    pass

class FPGATimeoutError(FPGAError):
    """Le FPGA n’a pas répondu dans le délai imparti."""
    pass

class FPGAValidationError(FPGAError):
    """Les données d’entrée n’ont pas passé la validation."""
    pass

class FPGAProtocolError(FPGAError):
    """La réponse du FPGA est mal formée ou inattendue."""
    pass

class FPGAAuthenticationError(FPGAError):
    """Levée lorsque le tag déchiffré échoue à l’authentification par rapport au tag original."""
    pass

class EncryptionError(IACQError):
    """Levée lorsqu’un chiffrement ou un déchiffrement ASCON échoue."""
    pass

class DataValidationError(IACQError):
    """Levée lorsque les données chargées depuis le fichier CSV échouent à la validation."""
    pass