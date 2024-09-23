import yaml
import requests
import argparse
import yaml
from typing import Any

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
        raise Exception(f"Erreur lors du téléchargement de {url}: {response.status_code}")

if __name__ == "__main__":
    # Configurer l'analyseur d'arguments
    parser: argparse.ArgumentParser = argparse.ArgumentParser(
        description="Télécharger et parser un manifest OpenTelemetry pour une version spécifique."
    )
    parser.add_argument(
        "--version", 
        required=True, 
        help="Version cible du manifest OpenTelemetry à télécharger (ex: 0.47.0)"
    )

    # Récupérer la version fournie par l'utilisateur
    args: argparse.Namespace = parser.parse_args()
    
    # Ouvrir et lire le fichier YAML
    with open('manifest.yaml', 'r') as file:
        manifest = yaml.safe_load(file)

    gomods = {}
    for flavor in ['otelcol-contrib', 'otelcol-k8s']:
        k8s = download_and_parse_yaml(args.version, flavor)
        manifest['dist']['version'] = k8s['dist']['version']
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
                raise Exception(f"Module {group} - {mod[0]} non trouvé")
        manifest[group]=newgroup

    print(yaml.dump(manifest, default_flow_style=False, sort_keys=False, indent=2))
