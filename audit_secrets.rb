
#  GitLab Secrets Audit Tool

- CI/CD project and group variables
- Runner tokens (project, group, and instance)
- Kubernetes tokens
- Deploy tokens and deploy keys

---

##  Files Generated

| File Path                                | Description                                |
|------------------------------------------|--------------------------------------------|
| `/tmp/gitlab_secrets_audit.log`          | Full audit log with successes and failures |
| `/tmp/gitlab_secrets_audit_failures.json` | JSON report of failures (only if any found) |

---

##  Running the Audit in Docker (GitLab container)

### 1.  Copy the script into the GitLab container

```bash
docker cp gitlab_secrets_audit.rb gitlab:/tmp/
```
---

### 2.  Run the script inside the container

```bash
docker exec -it gitlab ruby /tmp/gitlab_secrets_audit.rb
```

---

### 3.  Retrieve the logs

#### Copy the main log:

```bash
docker cp gitlab:/tmp/gitlab_secrets_audit.log ./
```

#### Copy the failure report (only if generated):

```bash
docker cp gitlab:/tmp/gitlab_secrets_audit_failures.json ./
```
---

##  Notes

- Only failures result in a JSON file.
- If no failures occur, any existing `gitlab_secrets_audit_failures.json` file is deleted.
---

