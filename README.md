# Bash Toolkit

A production-ready collection of optimized Bash scripts to simplify cloud operations, log parsing, data processing, and validation tasks on Google Cloud Platform (BigQuery, Cloud Storage) and local environments.

---

## Prerequisites & System Requirements

To use all utility scripts in this repository, ensure you have the following command-line utilities installed and available in your shell's `PATH`:

| Utility | Purpose | Installation Guide / Note |
| :--- | :--- | :--- |
| `bq` | BigQuery Operations | Component of the [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) |
| `gcloud` | Google Cloud CLI (Storage operations) | Component of the [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) |
| `parallel` | GNU Parallel (multi-threaded copying) | Install via `apt-get install parallel` or `brew install parallel` |
| `jq` | JSON parser and formatter | Install via `apt-get install jq` or `brew install jq` |
| `awk` | Text processor (used in csv splitting) | Pre-installed on most macOS & Linux environments |
| `sed` / `grep` | Text filtering and substitutions | Pre-installed |

---

## Scripts Directory & Catalog

### 1. BigQuery Table Copy (`bq_table_copy.sh`)
Copies multiple BigQuery tables in parallel from a source dataset to a destination dataset using GNU `parallel` and the `bq cp` utility.

* **Usage**:
  ```bash
  ./bq_table_copy.sh -s <SRC_PROJECT:DATASET> -d <DEST_PROJECT:DATASET> -t <TABLES> [OPTIONS]
  ```
* **Options**:
  * `-s <PROJECT:DATASET>`: Source project and dataset (e.g., `"co-repository-some:some_dataset"`). **(Required)**
  * `-d <PROJECT:DATASET>`: Destination project and dataset. **(Required)**
  * `-t <TABLE_LIST>`: Comma-separated list of table names to copy (e.g., `"table1,table2,table3"`). **(Required)**
  * `-j <NUM>`: Number of parallel copy jobs to run concurrently (Default: `4`).
  * `-f`: Force overwrite destination tables if they already exist.
  * `-l <LOG_DIR>`: Specify a directory to store execution logs (Default: Creates a temporary directory).
  * `-v`: Verbose mode (displays individual `bq cp` commands as they execute).
  * `-h`: Display help message.
* **Example**:
  ```bash
  ./bq_table_copy.sh -s "co-ingest:raw_dataset" -d "co-prod:dataset" -t "usuarios,consultas" -j 8 -f
  ```

---

### 2. BigQuery Cleanup (`bq_cleanup.sh`)
Safely deletes multiple BigQuery tables within a specified dataset. Features a dry run safety mode and an explicit confirmation requirement to prevent accidental loss of data.

* **Usage**:
  ```bash
  ./bq_cleanup.sh <PROJECT> <DATASET> <TABLES> [<DRY_RUN>] [<SURE>]
  ```
* **Arguments**:
  * `<PROJECT>`: BigQuery project ID.
  * `<DATASET>`: BigQuery dataset ID.
  * `<TABLES>`: Space-separated list of table names (e.g., `"table1 table2"`).
  * `<DRY_RUN>`: Set to `"true"` (default) to simulate actions; set to `"false"` to perform actual deletions.
  * `<SURE>`: Must be set to `"true"` to proceed when `DRY_RUN` is `"false"`.
* **Example**:
  ```bash
  # Dry Run:
  ./bq_cleanup.sh my-project my_dataset "temp_table1 temp_table2" true false

  # Actual Deletion:
  ./bq_cleanup.sh my-project my_dataset "temp_table1 temp_table2" false true
  ```

---

### 3. GCS Hierarchical Compose (`cloud_storage_compose_many.sh`)
Merges more than 32 files on Google Cloud Storage (GCS) into a single destination file. Since GCS imposes a hard limit of 32 source objects per `objects compose` command, this script recursively merges files in batches of 32 (tree-like reduction), deletes intermediate composite objects, and removes original source files on success.

* **Usage**:
  ```bash
  ./cloud_storage_compose_many.sh <bucket> <src_file_pattern> <dest_dir_pattern> <dest_file_name>
  ```
* **Arguments**:
  * `<bucket>`: GCS bucket name (e.g. `my-gcs-bucket`).
  * `<src_file_pattern>`: File path pattern matching files to compose (e.g. `folder/subfolder/part-*`).
  * `<dest_dir_pattern>`: Destination folder path inside the bucket (e.g. `folder/combined/`).
  * `<dest_file_name>`: Desired filename of the composed file (e.g. `merged_dataset.csv`).
* **Example**:
  ```bash
  ./cloud_storage_compose_many.sh my-gcs-bucket "data/raw/myfile-*" "data/combined/" "combined_file.csv"
  ```

---

### 4. RIPS Key Counter (`count_rips.sh`)
Finds all JSON files representing Colombian RIPS files (Registro Individual de Prestación de Servicios de Salud) in a specified directory, and prints the maximum serial number (`consecutivo`) under a user-defined service type key (e.g. `ap` for procedures, `ac` for consultations, `am` for medications).

* **Usage**:
  ```bash
  ./count_rips.sh <key> <path>
  ```
* **Arguments**:
  * `<key>`: The service key inside the JSON structure (e.g., `ac`, `ap`, `am`).
  * `<path>`: The local directory containing the `.json` files.
* **Example**:
  ```bash
  ./count_rips.sh ac ./data/raw
  ```

---

### 5. RIPS User Counter (`count_users_rips.sh`)
Scans a local directory for JSON files, navigates the root `usuarios` array, and extracts the maximum serial number (`consecutivo`) directly defined under the users array.

* **Usage**:
  ```bash
  ./count_users_rips.sh <path>
  ```
* **Arguments**:
  * `<path>`: The local directory containing the `.json` files.
* **Example**:
  ```bash
  ./count_users_rips.sh ./data/raw
  ```

---

### 6. CSV Key and Log Parser (`extract_keys.sh`)
Processes a stream of JSON schema validation logs from standard input, maps error locations to the actual lines in source JSON files, categories the error types, and outputs a formatted RFC 4180-compliant CSV dataset containing troubleshooting metadata.

* **Usage**:
  ```bash
  cat logfile.log | BASE_DIR_ENV=/path/to/raw/data ./extract_keys.sh > output.csv
  ```
* **Environment Variables**:
  * `BASE_DIR_ENV`: The base directory path where the raw `.json` files are stored. The script combines this path with the relative filepath extracted from logs to read the exact error lines.
* **CSV Output Fields**:
  1. `tercero`: Tech provider directory name.
  2. `periodo`: Reporting period folder.
  3. `modelo`: Data model type.
  4. `factura`: Bill name extracted from filename.
  5. `nit`: NIT code extracted from filename.
  6. `linea`: 1-based JSON line number.
  7. `json`: Exact text of the line from the source file.
  8. `error`: Categorized error type (e.g. `missing field`, `invalid datatype`, `wrong date`).
  9. `key`: The target JSON key causing the validation error.
  10. `esperado`: Expected datatype or format.
  11. `actual`: Found datatype or format.

---

### 7. Large CSV Splitter (`split_csv.sh`)
Splits large CSV files into smaller chunks of a specified maximum size in Megabytes. It parses the file line-by-line using `awk` for memory efficiency and ensures that the header row is preserved and prepended to every split chunk. Supports both individual files and directory scanning.

* **Usage**:
  ```bash
  ./split_csv.sh <output_directory> <max_size_in_mb> <input_path1> [<input_path2> ...]
  ```
* **Arguments**:
  * `<output_directory>`: Directory where split CSV chunks will be created.
  * `<max_size_in_mb>`: Maximum size of each split chunk in MB (e.g., `50`).
  * `<input_path>`: One or more paths to CSV files or directories containing CSV files.
* **Example**:
  ```bash
  ./split_csv.sh ./output_splits 15 ./data/large_dataset.csv ./more_data/
  ```

---

## Automation via Makefile

The repository includes a `MakeFile` containing shortcuts for common log processing flows.

### `make_dataset`
Cleans up null bytes and directory paths from a RIPS validation errors log, matches errors to JSON files using `extract_keys.sh`, and outputs an clean CSV dataset named `json_errors.csv`.

* **Command**:
  ```bash
  LOG_DATE_VAR="<DATE_SUBSTRING>" BASE_DIR_ENV="<RAW_DATA_PATH>" make make_dataset
  ```
* **Example**:
  ```bash
  LOG_DATE_VAR="2026-06-03" BASE_DIR_ENV="/mnt/c/data/" make make_dataset
  ```

---

## Authors & Contributors
* Orlando Reyes (`evoreyes@epsssanitas.com`)
* TheLionCoder
