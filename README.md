# Healthcare Coverage AI

> **Synthetic data only, not for clinical use.**

Healthcare Coverage AI is a prior authorization copilot. A clinic's prior auth coordinator creates a case (patient, requested service, supporting documents), and the system checks each payer coverage criterion against the patient's evidence. Every criterion comes back as **Met**, **Not met**, or **Insufficient evidence**, with a rationale and a citation to the exact page and passage it relied on. A human reviews every result and can override any of them.

## Run locally

Requires Docker.

```sh
cp .env.example .env   # then set POSTGRES_PASSWORD
make up                # Postgres 17 + pgvector on localhost:5433, returns when healthy
make psql              # psql shell inside the container
make help              # all targets
```
