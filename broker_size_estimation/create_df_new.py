import os
from os import listdir
from os.path import isfile, join
import re
import statistics
import pandas as pd
import logging

logging.basicConfig(level=logging.INFO)

def to_bytes(val, bsize=1024):
    """Convert memory size from string to bytes."""
    if 'KiB' in val:
        return float(val.replace('KiB', '')) * bsize
    if 'MiB' in val:
        return float(val.replace('MiB', '')) * bsize * bsize
    if 'K' in val:
        return float(val.replace('K', '')) * bsize
    if 'M' in val:
        return float(val.replace('M', '')) * bsize * bsize
    return float(val)

def parse_ram(files, path):
    """Parse RAM usage from files."""
    res_max = {}
    res_avg = {}
    for file_name in files:
        file_path = os.path.join(path, file_name)
        logging.info(f"Processing RAM file: {file_path}")

        parts = file_name.split('/')[-1].split('_')
        sim_num = int(parts[0].replace('sim', ''))
        data_size = int(re.sub("[^0-9]", "", parts[1]))
        pub_num = int(re.sub("[^0-9]", "", parts[2]))
        sub_num = int(re.sub("[^0-9]", "", parts[3]))
        retain = parts[4]
        qos = int(parts[5].replace('qos', ''))
        topics = int(parts[6].replace('topics', '').replace('.txt', ''))

        key = (sim_num, pub_num, sub_num, data_size, retain, qos, topics)

        if key not in res_max:
            res_max[key] = {}
            res_avg[key] = {}

        with open(file_path) as f:
            lines = f.readlines()

        parse = [li.replace(' \x1b[2J\x1b[Hmosquitto-broker', '').replace(' /', '').split('\t') for li in ''.join(lines).split('\n') if li]

        # Filter out invalid memory entries
        ram_results = [li[-1].split(' ')[0] for li in parse if re.match(r'^\d+(\.\d+)?(K|M)iB$', li[-1].split(' ')[0])]
        
        if not ram_results:
            continue

        byte_results = [to_bytes(v) for v in ram_results]
        res_max[key] = round(max(byte_results))
        res_avg[key] = round(statistics.mean(byte_results))

    return res_max, res_avg

def parse_db(files, path, skipped_files):
    """Parse database size from files."""
    res = {}
    for file_name in files:
        file_path = os.path.join(path, file_name)
        logging.info(f"Processing DB file: {file_path}")

        with open(file_path) as f:
            lines = f.readlines()

        # Check if the file is empty
        if not lines:
            logging.warning(f"Skipped empty file: {file_path}")
            skipped_files.append(file_path)
            continue

        parts = file_name.split('/')[-1].split('_')
        sim_num = int(parts[1].replace('sim', ''))
        data_size = int(re.sub("[^0-9]", "", parts[2]))
        pub_num = int(re.sub("[^0-9]", "", parts[3]))
        sub_num = int(re.sub("[^0-9]", "", parts[4]))
        retain = parts[5]
        qos = int(parts[6].replace('qos', ''))
        topics = int(parts[7].replace('topics', '').replace('.txt', ''))

        key = (sim_num, pub_num, sub_num, data_size, retain, qos, topics)

        if key not in res:
            res[key] = {}

        # Convert content to bytes
        try:
            res[key] = to_bytes(''.join(lines).replace('\n', ''))
        except ValueError:
            logging.warning(f"Skipping file with invalid data: {file_path}")
            skipped_files.append(file_path)

    return res

def process_folder(path):
    """Process all RAM and DB files in a directory."""
    only_ram = [f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f)) and 'ls_' not in f and not f.startswith('.')]
    only_ls = [f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f)) and 'ls_' in f and not f.startswith('.')]

    skipped_files = []  # To store the skipped files

    result_max, result_avg = parse_ram(only_ram, path)
    result_db = parse_db(only_ls, path, skipped_files)

    return result_avg, result_db, skipped_files

def main():
    base_folder = "results_new/"
    data = []
    all_skipped_files = []

    for dir_name in os.listdir(base_folder):
        dir_path = os.path.join(base_folder, dir_name)
        if os.path.isdir(dir_path):
            result_avg, result_db, skipped_files = process_folder(dir_path)
            all_skipped_files.extend(skipped_files)

            for key, ram_usage in result_avg.items():
                sim_num, pub_num, sub_num, message_size, retain, qos, topics = key
                database_size = result_db.get(key, None)

                data.append({
                    'simulation_number': sim_num,
                    'publisher_number': pub_num,
                    'subscriber_number': sub_num,
                    'message_size': message_size,
                    'retain': retain,
                    'qos': qos,
                    'topics': topics,
                    'ram_usage': ram_usage,
                    'database_size': database_size
                })

    df = pd.DataFrame(data)
    df.to_csv('results_new.csv', index=False)  # Save as CSV file
    print("DataFrame saved as 'results_new.csv'")
    print(df)

    if all_skipped_files:
        print("Skipped the following files due to being empty or having invalid data:")
        for file in all_skipped_files:
            print(file)

if __name__ == '__main__':
    main()
