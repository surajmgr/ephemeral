# Ephemeral Storage Template (Northflank & pCloud Edition)

Running Typesense (or other stateful services) on ephemeral storage with persistence backed by pCloud snapshots.

## Why?
Cloud providers like Northflank often offer limited free ephemeral storage (e.g., 2GB in `/tmp` or root fs) but charge for persistent volumes. This setup allows you to run services "statelessly" while persisting data to your pCloud account.

## Structure

- `services/typesense/`: Typesense service definition.
  - `backup.sh`: Deploys snapshots to pCloud. Handles retention (keeps last X backups)
  - `restore.sh`: Fetches data from pCloud on startup.
- `scripts/`: Helpers.

## pCloud Setup (Important!)

You need to authorize `rclone` with your pCloud account to get the token.

1.  **Install Rclone locally**: [https://rclone.org/install/](https://rclone.org/install/)
2.  **Run Config**:
    ```bash
    rclone config
    ```
    -   **n** (New remote)
    -   name: `pcloud` (or whatever, doesn't matter for the token)
    -   Storage: Search for `pcloud`
    -   Follow the authentication flow in your browser.
3.  **Get the Token**:
    -   Run `rclone config show` or `cat ~/.config/rclone/rclone.conf`.
    -   Find the `token = {...}` line.
    -   Copy the **entire JSON string** (including curly braces).

## Deployment on Northflank

1.  **Create Service**:
    -   Select **Dockerfile** build (Path: `services/typesense/Dockerfile`, Context: Project Root).
    -   Port: `8108` (HTTP).

2.  **Environment Variables**:
    Add the following variables (you can use **Secrets** for the token):

    | Key | Value | Notes |
    | :--- | :--- | :--- |
    | `TYPESENSE_API_KEY` | `your-secure-key` | |
    | `TYPESENSE_HOST` | `http://localhost:8108` | |
    | `BACKUP_INTERVAL` | `3600` | Backup every hour (seconds) |
    | `BACKUP_RETENTION_COUNT` | `10` | Keep last 10 snapshots |
    | `CLOUD_DEST` | `remote:backups/typesense` | `remote` corresponds to the rclone config name created dynamically |
    | `RCLONE_CONFIG_REMOTE_TYPE` | `pcloud` | Tells rclone this is pCloud |
    | `RCLONE_CONFIG_REMOTE_TOKEN` | `{"access_token":...}` | **Paste the JSON token here.** |

3.  **Deploy**:
    -   Northflank will build the image.
    -   On start, it will fail to find a backup (first run) and start fresh.
    -   After 1 hour (or `BACKUP_INTERVAL`), it will upload the first snapshot to pCloud.
    -   If the container restarts, it will download that snapshot.

## Local Testing via Docker Compose

1.  Copy `.env.example` to `.env`.
2.  Paste your pCloud token into `RCLONE_CONFIG_REMOTE_TOKEN`.
3.  `docker-compose up --build`.

## Troubleshooting

-   **"Failed to restore"**: Check if `CLOUD_DEST` path exists in pCloud.
-   **Token Expired**: pCloud tokens might refresh. Rclone handles this if the writeable config is saved, but in ephemeral envs, we inject the token. The `token` JSON usually contains a `refresh_token` which allows rclone to generate new access tokens. Ensure you copied the *entire* JSON object.
