import yaml
import requests
import argparse
import yaml
import re
import functools
from typing import Any

class ManifestError(Exception):
    """
    Classe d'exception déclenchée dans le cas où une erreur survient pendant la fusion des manifests.
    """
    def __init__(self, message: str):
        super().__init__(message)
        self.message = message

    def __str__(self):
        return self.message

def check_manifest_error(func):
    """
    Décorateur qui vérifie si une exception ManifestError est déclenchée lors de l'appel d'une fonction et affiche l'erreur sur la sortie standard si c'est le cas.

    Args:
        func (Callable): La fonction à appeler.

    Returns:
        Callable: La fonction appelée.
    """
    @functools.wraps(func)
    def inner(*args, **kwargs):
        try:
            # Appeler la fonction avec les arguments
            return func(*args, **kwargs)
        except ManifestError as e:
            # Afficher l'erreur sur la sortie standard
            print(e)
            # Déclencher une interruption du script
            raise SystemExit(e)
    return inner

@check_manifest_error
def download_and_parse_yaml(version: str, flavor: str) -> Any:
    """
    Télécharge et parse le fichier YAML manifest.yaml d'OpenTelemetry pour la version et la déclinaison spécifiées.

    Args:
        version (str): La version du manifest OpenTelemetry à télécharger (ex: "0.47.0").
        flavor (str): La déclinaison du manifest OpenTelemetry à télécharger (ex: "otelcol-k8s").

    Returns:
        Any: L'objet Python résultant du parsing du contenu YAML.
    """
    # URL du fichier avec la version spécifiée par l'utilisateur
    url: str = f"https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-releases/v{version}/distributions/{flavor}/manifest.yaml"

    # Faire la requête GET pour récupérer le contenu du fichier
    response: requests.Response = requests.get(url)

    # Vérifier si la requête a réussi (code 200)
    if response.status_code == 200:
        # Parser le contenu YAML et retourner l'objet Python
        return yaml.safe_load(response.content)
    else:
        raise ManifestError(f"Erreur lors du téléchargement de {url}: {response.status_code}")

def check_value_errors(func):
    """
    Décorateur qui vérifie si une exception ManifestError est déclenchée lors de l'appel d'une fonction et affiche l'erreur sur la sortie standard si c'est le cas.

    Args:
        func (Callable): La fonction à appeler.

    Returns:
        Callable: La fonction appelée.
    """
    @functools.wraps(func)
    def inner(*args, **kwargs):
        try:
            # Appeler la fonction avec les arguments
            return func(*args, **kwargs)
        except ValueError as e:
            # Afficher l'erreur sur la sortie standard
            print(f"check_value_error: {e}")
            # Déclencher une interruption du script
            raise SystemExit(e)
    return inner

@check_value_errors
def validate_version(version: str):
    """
    Fonction de normalisation qui supprime le potentiel "v" en début de chaîne et valide le format de la version.

    Args:
        version (str): La version OpenTelemetry à normaliser.

    Returns:
        str: La version normalisée (ex: 0.47.0).
    """
    # Vérifier que la version est valide (au format x.x.x)
    if not re.match(r'^\d+\.\d+\.\d+$', version):
        raise ValueError(f"La version {version} est invalide")

def main():
    # Configurer l'analyseur d'arguments
    parser: argparse.ArgumentParser = argparse.ArgumentParser(
        description="Télécharger et parser un manifest OpenTelemetry pour une version spécifique."
    )
    parser.add_argument(
        "--version",
        required=True, 
        help="Version cible du manifest OpenTelemetry à télécharger (ex: 0.47.0)",
    )

    # Récupérer la version fournie par l'utilisateur
    args: argparse.Namespace = parser.parse_args()
    VERSION: str = args.version
    validate_version(VERSION)

    # Ouvrir et lire le fichier YAML
    with open('manifest-template.yaml', 'r') as file:
        manifest = yaml.safe_load(file)

    gomods = {}
    for flavor in ['otelcol-contrib', 'otelcol-k8s']:
        k8s = download_and_parse_yaml(VERSION, flavor)
        manifest['dist']['version'] = k8s['dist']['version']
        if 'otelcol_version' in k8s['dist']:
            manifest['dist']['otelcol_version'] = k8s['dist']['otelcol_version']
        for group in ['extensions', 'exporters', 'processors', 'receivers', 'connectors', 'providers']:
            for ext in k8s[group]:
                mod = (ext['gomod']).split()
                gomods[mod[0]]=mod[1]

    for group in ['extensions', 'exporters', 'processors', 'receivers', 'connectors']:
        newgroup = []
        for ext in manifest[group]:
            mod = (ext['gomod']).split()
            if mod[0] in gomods:
                newgroup.append( { "gomod": f"{mod[0]} {gomods[mod[0]]}" })
            else:
                raise ManifestError(f"Module {group} - {mod[0]} non trouvé")
        manifest[group]=newgroup

    print(yaml.dump(manifest, default_flow_style=False, sort_keys=False, indent=2, width=128))

if __name__ == "__main__":
    main()
