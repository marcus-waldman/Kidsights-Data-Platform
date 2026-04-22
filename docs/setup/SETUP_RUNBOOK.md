# Kidsights Data Platform — Setup Runbook (Claude Desktop)

> **Who this is for:** a new collaborator who wants the Kidsights Data Platform working on their machine.
> **How to use it:** open this file in Claude Desktop, paste its contents into the chat, and say _"walk me through this."_ Claude will then ask you questions one at a time and guide you through setup.
> **Time to complete:** 20–40 minutes once API keys and the database snapshot are in hand.

---

## For Claude reading this runbook

You are walking a human through setting up the Kidsights Data Platform on their machine. Proceed **one section at a time**. Ask the questions inline, wait for their reply, then guide them through the matching step. Do not skip ahead. Do not try to do things for them — they are at their own terminal.

**Standing rules while running this runbook:**

1. When showing filesystem paths on screen, use Windows backslash form (`C:\Users\...`). When showing `.env` file contents, use forward slashes (`C:/Users/...`) — backslashes in `.env` silently break on Windows.
2. Never ask the user to paste API keys, tokens, or `.env` file contents into the chat. Only ask for file **paths**.
3. On any failure you can't resolve in one or two turns, jump straight to **§ 6 — If it fails** and help the user file a GitHub issue. Don't let them spiral.
4. If the user tells you they only want to _query_ existing data (not run any pipeline), skip § 2's branching question and jump straight to § 4 (database snapshot), then § 7.
5. This runbook is pipeline-aware: the credential section (§ 3) only asks for what the user's chosen pipeline needs. Don't request IPUMS keys from a MN26 user.

Begin with § 1.

---

## § 1. Pre-flight check

Say to the user:

> "Before we configure anything, I want to confirm a few prerequisites. I'll ask about each one — just answer yes/no or paste the output."

Ask in order. For each, wait for their reply before moving to the next.

### 1.1 — Repo cloned?

> "Have you already cloned the Kidsights-Data-Platform repository onto this machine?"

If **no**, give them:

```bash
git clone https://github.com/marcus-waldman/Kidsights-Data-Platform.git
cd Kidsights-Data-Platform
```

If **yes**, ask them to confirm they're running commands from the repo root (where `run_mn26_pipeline.R` and `.env.template` live).

### 1.2 — R 4.5.1+?

> "Run this and paste the first line of output:"

```
"C:\Program Files\R\R-4.5.1\bin\R.exe" --version
```

Expected: a line like `R version 4.5.1 (2025-06-13) -- "Great Square Pyramid"`. If R isn't at that path, ask them where it is and adjust all subsequent R commands accordingly. If they don't have R 4.5.1+, direct them to https://cran.r-project.org/bin/windows/base/ before continuing.

### 1.3 — Python 3.13+?

> "Run this and paste the output:"

```
py --version
```

Expected: `Python 3.13.x` or newer. On Windows, `py` is the launcher — it's what the platform expects (see `PYTHON_EXECUTABLE` later). If they don't have Python 3.13+, direct them to https://www.python.org/downloads/ before continuing.

### 1.4 — Packages installed?

Tell the user that R and Python packages need to be installed. Give them these commands to run:

**R packages** (run inside R):

```r
install.packages(c("dplyr", "tidyr", "stringr", "yaml", "REDCapR", "arrow", "duckdb", "reticulate"))
```

**Python packages** (run in the terminal):

```bash
pip install duckdb pandas pyyaml structlog python-dotenv
```

If they chose ACS or NHIS later, they'll also need `ipumspy` and `requests`. If they chose NSCH, they'll need `pyreadstat`. Flag this now but don't install yet — wait until § 2 tells you which pipeline they want.

Once all four checks pass, proceed to § 2.

---

## § 2. Which pipeline do you want to run first?

Say to the user:

> "The platform has eight pipelines, but you almost certainly only want to run one of them to start. Different pipelines need different credentials, so this answer decides what we configure next. Which of these best matches what you're trying to do?"

Present these options:

| Option | Use case |
|---|---|
| **MN26** | Minnesota 2026 REDCap survey. **Recommended first run** — this runbook's smoke test targets MN26. |
| **NE25** | Nebraska 2025 REDCap survey. |
| **ACS** | IPUMS USA census data extraction. |
| **NHIS** | IPUMS health survey data extraction. |
| **NSCH** | National Survey of Children's Health. Needs raw SPSS files downloaded manually. |
| **Just query the DB** | You only want to read from a database snapshot Marcus is sending you. No pipeline-running needed. |
| **Imputation / Raking / IRT Calibration** | These depend on other pipelines running first. Redirect: tell the user these require prior pipeline outputs (Imputation needs NE25; Raking needs ACS + NHIS + NSCH; IRT Calibration needs NE25 + NSCH) and point them at `CLAUDE.md` for the dependency detail. Then ask which _upstream_ pipeline they'd like to start with, and treat that as their answer. |

Record the answer. This determines which branch of § 3 you follow.

---

## § 3. Credentials and `.env`

This is the section with the most variation. Only do the steps for the user's chosen pipeline.

### 3.1 — Start the `.env` file (all branches)

Tell the user:

> "Everything we configure next lives in a file called `.env` at the repo root. It's gitignored and never committed. Let's copy the template."

Give them (from repo root):

```bash
cp .env.template .env
```

On Windows PowerShell: `Copy-Item .env.template .env`

Tell them to open `.env` in a text editor (Notepad, VS Code, etc.) — they'll edit it in the next steps. Keep it open.

### 3.2 — `PYTHON_EXECUTABLE` (all branches)

Every branch needs this because R scripts call Python and the hardcoded name `python` fails on Windows (see `R/utils/environment_config.R::get_python_path()` for why).

Ask the user:

> "Run `py -c \"import sys; print(sys.executable)\"` and paste the output."

Take that path, convert backslashes to forward slashes, and tell them to set in `.env`:

```
PYTHON_EXECUTABLE=C:/Users/YOUR_USERNAME/AppData/Local/Programs/Python/Python313/python.exe
```

(Replace with their actual path. Forward slashes only.)

### 3.3 — Branch-specific credentials

Now branch on § 2's answer.

#### Branch: MN26

MN26 needs two external credentials: **REDCap** and **FRED**.

**REDCap API credentials CSV** — this is a file Marcus provides.

> "Marcus is sending you (or has sent you) a file called `kidsights_redcap_api.csv`. It's a small CSV with columns `project, pid, api_code` containing API tokens for the MN26 REDCap project. Save it somewhere outside the repo — by convention, at `C:\Users\<your-username>\my-APIs\kidsights_redcap_api.csv`."

Then edit `.env`:

```
REDCAP_API_CREDENTIALS_PATH=C:/Users/YOUR_USERNAME/my-APIs/kidsights_redcap_api.csv
```

**FRED API key** — needed for CPI inflation adjustment in the income transformation step.

> "Register a free account at https://fred.stlouisfed.org/, then generate a key at https://fredaccount.stlouisfed.org/apikeys. Save the key (a single line of text) to `C:\Users\<your-username>\my-APIs\FRED.txt`."

Then edit `.env`:

```
FRED_API_KEY_PATH=C:/Users/YOUR_USERNAME/my-APIs/FRED.txt
```

Leave `IPUMS_API_KEY_PATH` unset or point it at a nonexistent path — MN26 doesn't touch IPUMS.

#### Branch: NE25

Same credentials as MN26 (REDCap CSV + FRED key), but the REDCap CSV contains **four** project rows instead of one. Tell the user:

> "Marcus is sending you a CSV with API tokens for four NE25 REDCap projects (pids 7679, 7943, 7999, 8014). The schema is `project, pid, api_code`. Save it at `C:\Users\<your-username>\my-APIs\kidsights_redcap_api.csv` and then set `REDCAP_API_CREDENTIALS_PATH` in `.env` accordingly."

Then walk them through FRED as in the MN26 branch.

#### Branch: ACS

ACS needs an **IPUMS API key** (and nothing else credential-wise).

> "Register at https://usa.ipums.org/ (create an account, request access to USA data), then go to https://account.ipums.org/api_keys and copy the generated key. Save it as a single-line text file at `C:\Users\<your-username>\my-APIs\IPUMS.txt`."

Then edit `.env`:

```
IPUMS_API_KEY_PATH=C:/Users/YOUR_USERNAME/my-APIs/IPUMS.txt
```

Also remind them to install the Python packages mentioned in § 1.4: `pip install ipumspy requests`.

#### Branch: NHIS

Same as ACS — just the IPUMS key. The same key works for both USA (ACS) and NHIS. If they already registered for USA, they don't need to register again, but they do need to accept the NHIS terms of use at https://nhis.ipums.org/.

#### Branch: NSCH

NSCH does **not** use an API. Instead, the user manually downloads SPSS `.sav` files from the Data Resource Center.

> "Go to https://www.childhealthdata.org/dataset and request the SPSS NSCH files for the years you want (2016 through 2023 are supported). You'll be emailed a download link after approval — turnaround is usually same-day. Once you have the `.sav` files, place each one at `<repo>\data\nsch\{year}\<whatever-filename>.sav`."

No API key goes into `.env` for this branch.

#### Branch: Just query the DB

Skip directly to § 4.

### 3.4 — Verify the `.env` loaded

Once the user has saved `.env`, have them run:

```bash
py -c "from python.db.connection import DatabaseManager; print(DatabaseManager().test_connection())"
```

Expected output: `True`

If it prints `False` or errors, the most common causes are:
1. `.env` isn't at the repo root (it must be at the same level as `run_mn26_pipeline.R`).
2. `KIDSIGHTS_DB_PATH` is pointing at a nonexistent file.
3. `data/duckdb/` directory doesn't exist yet (that's fine — § 4 handles it).

If you can't diagnose in two turns, jump to § 6.

---

## § 4. Place the database snapshot

Say to the user:

> "The Kidsights database isn't in git and isn't regenerated automatically — it's a ~1 GB DuckDB file that Marcus sends out-of-band. I'll assume you've received it (or you will soon). Let's make a home for it."

### 4.1 — Create the target directory

From the repo root:

```bash
mkdir -p data/duckdb
```

Or on Windows PowerShell:

```powershell
New-Item -ItemType Directory -Path data\duckdb -Force
```

### 4.2 — Drop the file in

Tell the user:

> "Marcus will send you a file named `kidsights_local.duckdb`. When it arrives, place it at `<repo>\data\duckdb\kidsights_local.duckdb` exactly — filename included. Don't rename it."

### 4.3 — Verify

Re-run the smoke test:

```bash
py -c "from python.db.connection import DatabaseManager; print(DatabaseManager().test_connection())"
```

Expected: `True`.

Then confirm the snapshot has real data:

```bash
py -c "from python.db.connection import DatabaseManager; db = DatabaseManager(); \
with db.get_connection(read_only=True) as con: \
    print(con.execute('SELECT COUNT(*) FROM ne25_raw').fetchone())"
```

Expected: a tuple like `(4966,)` — the exact count will depend on when Marcus cut the snapshot. A zero or error means the file didn't land correctly.

If the user chose **Just query the DB** in § 2, skip to § 7 now. Otherwise continue to § 5.

---

## § 5. Smoke-test run — MN26 pipeline

> **Note:** this section runs the MN26 pipeline specifically, because it's the lightest-touch pipeline and exercises REDCap auth, `.env` loading, R/Python handoff, and DB writes all at once. If the user picked **NE25**, they can follow the same structure using `run_ne25_pipeline.R` instead. For **ACS / NHIS / NSCH**, point them at `CLAUDE.md`'s pipeline commands and skip to § 7.

### 5.1 — Dry run (no DB writes)

Tell the user:

> "Let's first run MN26 in skip-database mode. This exercises the REDCap auth and transformation logic without touching your DB."

```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" run_mn26_pipeline.R --skip-database
```

Expected: completes in about 1–2 seconds (with stubbed data) or a minute or so (with a real REDCap pull). Final log lines should report record counts and no fatal errors.

If this fails, go to § 6.

### 5.2 — Real run

If the dry run succeeded, run for real:

```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_mn26_pipeline.R
```

Expected: a few seconds to a few minutes depending on REDCap responsiveness. Success signals:
- Last few log lines report DB writes with row counts.
- No R errors.
- A new or updated table appears in the DB (`mn26_raw`, `mn26_transformed`, etc.).

Verify the write landed:

```bash
py -c "from python.db.connection import DatabaseManager; db = DatabaseManager(); \
with db.get_connection(read_only=True) as con: \
    print(con.execute('SELECT COUNT(*) FROM mn26_raw').fetchone())"
```

Expected: a non-zero count.

If either command failed, proceed to § 6.

---

## § 6. If it fails — file a GitHub issue

If the user got stuck at any step above and you couldn't unblock them in one or two turns, it's time to file an issue. This is the _right_ move — it turns a dead-end setup into a trackable problem Marcus can fix for the next person.

Say to the user:

> "We've hit something I can't resolve from here. The best thing to do now is file a GitHub issue — that way Marcus sees it, fixes it, and the runbook gets better for the next person. I'll give you a template to copy. You'll paste your error into it."

Give them the URL:

```
https://github.com/marcus-waldman/Kidsights-Data-Platform/issues/new
```

And this issue template (they should copy-paste into the issue body and fill in the blanks):

```markdown
Title: [Setup Runbook] <pipeline>: <one-line summary of failure>

### What I was trying to do
Setting up the Kidsights Data Platform following `docs/setup/SETUP_RUNBOOK.md`.
I got to § <section number, e.g. § 5.2>.

### What failed
<paste the exact command that failed>

### Error message
```
<paste the full error, including any R or Python traceback>
```

### My environment
- OS: Windows <version, e.g. 11 Pro 26200>
- R version: <from `R --version`>
- Python version: <from `py --version`>
- Pipeline I was trying: <MN26 / NE25 / ACS / NHIS / NSCH / just querying>

### My `.env` (SECRETS REDACTED)
<paste your .env with API key *paths* visible but the files they point to never shared. Do not include the contents of your REDCap CSV, IPUMS key, or FRED key.>

### What I've tried
<brief notes — "re-ran the smoke test", "checked that the file exists", etc.>
```

Before the user submits, **double-check with them**:

> "One last thing before you submit — the template asks you to paste your `.env`. I want to make sure you're only pasting the `.env` file itself (which has _paths_ to your API keys), not the contents of those key files themselves. Can you confirm you haven't pasted anything that starts with a REDCap token, an IPUMS key, or a FRED key?"

Wait for their confirmation. Then tell them to submit.

After submitting, wrap up:

> "Great — issue is filed. Marcus will see it and respond (usually within a day or two). In the meantime, if you have a pre-populated database snapshot you can still query it directly — want me to walk you through § 4 and § 7?"

End the session there.

---

## § 7. You're set up

If you got here, the user's environment is configured and (if applicable) MN26 ran end-to-end.

Say to the user:

> "You're good to go. Here's where to look next, depending on what you want to do:"

- **Run other pipelines** → `CLAUDE.md` at the repo root has canonical commands for all 8 pipelines, including the ones this runbook didn't cover.
- **Command cheatsheet** → `docs/QUICK_REFERENCE.md`.
- **Understand what MN26 just did** → `docs/mn26/pipeline_guide.qmd` (render with Quarto to HTML, or read as-is in a Markdown viewer — it's the authoritative MN26 documentation).
- **Deep-dive on setup / troubleshooting** → `docs/setup/INSTALLATION_GUIDE.md`. This runbook is a curated happy-path; the installation guide is the exhaustive reference.

Close with:

> "If anything breaks later, file an issue at https://github.com/marcus-waldman/Kidsights-Data-Platform/issues/new — that's the fastest way to get it fixed."

---

## Runbook metadata (for maintainers)

- **Last updated:** 2026-04-22
- **Authoritative install reference:** `docs/setup/INSTALLATION_GUIDE.md` (this runbook links; it does not duplicate)
- **Consumed by:** Claude Desktop (not Claude Code). This is a plain markdown runbook, not a `.claude/skills/*/SKILL.md`.
- **When to update:** if a new credential is introduced, a pipeline is renamed, `.env.template` adds a variable, or the DB-snapshot-handoff model changes.
