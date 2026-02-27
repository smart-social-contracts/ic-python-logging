"""CDK compatibility layer.

This module centralizes all imports from the Internet Computer CDK (currently Basilisk).
To switch CDKs, only this file needs to be modified.
"""

HAS_CDK = False

try:
    from basilisk import ic  # noqa: F401

    # Verify ic.print actually works (we might be imported but not in IC env)
    try:
        ic.print("")
        IN_IC_ENVIRONMENT = True
    except Exception:
        IN_IC_ENVIRONMENT = False

    HAS_CDK = True

except ImportError:
    ic = None  # type: ignore
    IN_IC_ENVIRONMENT = False


def _import_types():
    """Import CDK types for query function definitions.

    Returns a tuple of (Opt, Record, Vec, nat, query) or None if CDK unavailable.
    """
    try:
        from basilisk import Opt, Record, Vec, nat, query

        return Opt, Record, Vec, nat, query
    except ImportError:
        return None
