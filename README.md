Gestion des backups via Rsync.

- Rsync en mode serveur sur chaque poste --> rsyncd.conf
- le fichier ini décrit chaque poste (Quota, fréquence, file system du backup)
- Backup en mode incrémental via les "Hard link"
- Code legacy qui fonctionne bien mais en séquentiel. Besoin d'un mode asynchrone pour optimiser --> Async IO Python.
