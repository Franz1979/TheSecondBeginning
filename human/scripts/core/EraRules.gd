class_name EraRules
extends Resource

# Moltiplicatori legati al livello tecnologico del mondo, applicati (in futuro, non qui) alla
# simulazione umana — un file per era. In futuro: più livelli sbloccati man mano che il
# technology level avanza, con un meccanismo di cambio-era che aggiorna quali moltiplicatori
# sono attivi; quel meccanismo di progressione NON è implementato in questo passo, solo il dato.
# Classe isolata: nessun collegamento a HumanRules/HumanIndividual/HumanTypes qui — un futuro
# service che legge sia HumanRules che EraRules insieme deciderà come combinarli (es. la regola
# "longevity_multiplier si applica a tutte le fasce tranne CHILD" NON è implementata qui).

@export var longevity_multiplier: float = 1.0
