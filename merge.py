import yaml

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
