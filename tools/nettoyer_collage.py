"""Retire les lignes vides ajoutees par un collage dans le terminal.

Ton terminal ajoute une ligne vide avant chaque ligne collee, et une de plus a la fin. Ce programme remet les
fichiers du projet en etat. Il ne touche un fichier que si ses lignes 1, 3, 5... sont TOUTES vides ; un fichier
deja propre n'est jamais modifie. On peut le relancer sans risque.

Utilisation :
    python3 tools/nettoyer_collage.py          nettoie les fichiers
    python3 tools/nettoyer_collage.py --voir   montre ce qui serait nettoye, sans rien modifier
"""
import pathlib
import sys

VOIR = "--voir" in sys.argv
RACINE = pathlib.Path(__file__).resolve().parent.parent
EXTENSIONS = (".lua", ".py", ".md", ".sh", ".txt")

nettoyes = []
propres = []
ignores = []

for chemin in sorted(RACINE.rglob("*")):
    if not chemin.is_file() or chemin.suffix not in EXTENSIONS or ".git" in chemin.parts:
        continue
    brut = chemin.read_bytes()
    try:
        texte = brut.decode("utf-8")
    except UnicodeDecodeError:
        ignores.append((chemin, "ce n'est pas de l'UTF-8"))
        continue
    if "\r" in texte:
        ignores.append((chemin, "fins de ligne Windows"))
        continue
    lignes = texte.split("\n")
    if lignes and lignes[-1] == "":
        lignes = lignes[:-1]
    colle = len(lignes) >= 2 and all(l.strip() == "" for l in lignes[0::2])
    if not colle:
        propres.append(chemin)
        continue
    if not VOIR:
        chemin.write_bytes(("\n".join(lignes[1::2]) + "\n").encode("utf-8"))
    nettoyes.append((chemin, len(lignes), len(lignes) // 2))

verbe = "A nettoyer" if VOIR else "Nettoyes"
print(verbe + " :", len(nettoyes))
for chemin, avant, apres in nettoyes:
    print("  " + str(chemin.relative_to(RACINE)) + " : " + str(avant) + " lignes -> " + str(apres))
print("Deja propres :", len(propres))
for chemin, raison in ignores:
    print("Laisse tel quel : " + str(chemin.relative_to(RACINE)) + " (" + raison + ")")
if VOIR:
    print("(--voir) : rien n'a ete modifie.")
