class_name StoneSnapshot3D
extends RefCounted

# Rocce e sassi di UNA macrocella, già estratti dal gioco da GameStateReader (gli stessi che disegna il 2D).

# Rocce da disegnare (escluse le esaurite e quelle sotto il nero della nebbia, che il 2D copre): microcella -> centro in microcelle (stesso punto del 2D).
var rock_centers: Dictionary = {}
# Sassi: microcella della roccia -> quantità disponibile (la stessa che usa il 2D, già filtrata dalla nebbia).
var pebble_quantities: Dictionary = {}
# Centro di OGNI roccia, esaurite comprese: i sassi restano attorno anche a una roccia esaurita.
var all_centers: Dictionary = {}
