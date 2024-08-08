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
        parts = file_name.split('/')[-1].split('_')
        sim_num = int(parts[0].replace('sim', ''))
        data_size = int(re.sub("[^0-9]", "", parts[1]))
        pub_num = int(re.sub("[^0-9]", "", parts[2]))
        sub_num = int(re.sub("[^0-9]", "", parts[3]))
        retain = parts[4]
        qos = int(parts[5].replace('qos', ''))
        topics = int(parts[6].replace('topics', '').replace('.txt', ''))

        if sim_num not in res_max:
            res_max[sim_num] = {}
            res_avg[sim_num] = {}

        if pub_num not in res_max[sim_num]:
            res_max[sim_num][pub_num] = {}
            res_avg[sim_num][pub_num] = {}

        with open(file_path) as f:
            lines = f.readlines()

        parse = [li.replace(' \x1b[2J\x1b[Hmosquitto-broker', '').replace(' /', '').split('\t') for li in ''.join(lines).split('\n') if li]

        ram_results = [li[-1].split(' ')[0] for li in parse]
        byte_results = [to_bytes(v) for v in ram_results if v != '--']
        res_max[sim_num][pub_num][data_size] = round(max(byte_results))
        res_avg[sim_num][pub_num][data_size] = round(statistics.mean(byte_results))

        logging.info(f"Processed RAM file: {file_path}")

    return res_max, res_avg

def parse_db(files, path):
    """Parse database size from files."""
    res = {}
    for file_name in files:
        file_path = os.path.join(path, file_name)
        parts = file_name.split('/')[-1].split('_')
        sim_num = int(parts[1].replace('sim', ''))
        data_size = int(re.sub("[^0-9]", "", parts[2]))
        pub_num = int(re.sub("[^0-9]", "", parts[3]))

        if sim_num not in res:
            res[sim_num] = {}

        if pub_num not in res[sim_num]:
            res[sim_num][pub_num] = {}

        with open(file_path) as f:
            lines = f.readlines()

        res[sim_num][pub_num][data_size] = to_bytes(''.join(lines).replace('\n', ''))

        logging.info(f"Processed DB file: {file_path}")

    return res

def process_folder(path):
    """Process all RAM and DB files in a directory."""
    only_ram = [f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f)) and 'ls_' not in f and not f.startswith('.')]
    only_ls = [f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f)) and 'ls_' in f and not f.startswith('.')]

    result_max, result_avg = parse_ram(only_ram, path)
    result_db = parse_db(only_ls, path)

    return result_avg, result_db

def main():
    base_folder = "results_new/"
    data = []

    for dir_name in os.listdir(base_folder):
        dir_path = os.path.join(base_folder, dir_name)
        if os.path.isdir(dir_path):
            result_avg, result_db = process_folder(dir_path)
            for sim_key, sim_value in result_avg.items():
                for pub_num, message_sizes in sim_value.items():
                    for message_size, ram_usage in message_sizes.items():
                        database_size = result_db[sim_key][pub_num].get(message_size, None)

                        # Split file name to extract additional parameters
                        for file_name in os.listdir(dir_path):
                            if isfile(join(dir_path, file_name)) and file_name.startswith('sim'):
                                parts = file_name.split('_')
                                retain = parts[4]
                                qos = int(parts[5].replace('qos', ''))
                                topics = int(parts[6].replace('topics', '').replace('.txt', ''))

                                data.append({
                                    'simulation_number': sim_key,
                                    'publisher_number': pub_num,
                                    'subscriber_number': int(dir_name.split('_')[1][1:]),
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

if __name__ == '__main__':
    main()
