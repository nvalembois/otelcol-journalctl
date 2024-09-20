import yaml
import requests

# Remplacez par votre token GitHub personnel
REPO_OWNER = "open-telemetry"
REPO_NAME = "opentelemetry-collector-releases"
ARTIFACT_ID = "id_de_l_artefact"

# URL pour récupérer les artefacts
artifacts_base_url = f"https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/contents"

headers = {
    "Accept": "application/vnd.github.v3+json"
}

# Récupérer la liste des artefacts
response = requests.get(artifacts_url, headers=headers)
artifacts = response.json()

# Filtrer par ID de l'artefact (ou par nom si besoin)
for artifact in artifacts["artifacts"]:
    if artifact["id"] == int(ARTIFACT_ID):
        download_url = artifact["archive_download_url"]
        break

# Télécharger l'artefact
artifact_response = requests.get(download_url, headers=headers)
artifact_name = f"{artifact['name']}.zip"

# Sauvegarder l'artefact en tant que fichier zip
with open(artifact_name, "wb") as f:
    f.write(artifact_response.content)

print(f"Artefact {artifact_name} téléchargé avec succès !")

# Ouvrir et lire le fichier YAML
with open('manifest.yaml', 'r') as file:
    manifest = yaml.safe_load(file)
gomods = {}
for input in ['otelcol-contrib-manifest.yaml', 'otelcol-k8s-manifest.yaml']:
    with open(input, 'r') as file:
        k8s = yaml.safe_load(file)
    manifest['dist']['version'] = k8s['dist']['version']
    manifest['dist']['otelcol_version'] = k8s['dist']['otelcol_version']
    for group in ['extensions', 'exporters', 'processors', 'receivers', 'connectors']:
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
            newgroup.append( ext )
    manifest[group]=newgroup

print(yaml.dump(manifest, default_flow_style=False, sort_keys=False, indent=2))
