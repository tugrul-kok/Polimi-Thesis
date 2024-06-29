#!/usr/bin/env python3
from os import listdir
from os.path import isfile, join
import re
import statistics


def to_bytes(val, bsize=1024):
    b_val = 0
    # match = 'KiB K Kb KB kb'
    # print(re.search(r'\b'+match+r'\b', val))
    if 'KiB' in val:
        b_val = float(val.replace('KiB', '')) * bsize
        return b_val
    if 'MiB' in val:
        b_val = float(val.replace('MiB', '')) * bsize * bsize
        return b_val
    # return here ensure it doesn't enter in the "ls function" part --> shit

    if 'K' in val:
        b_val = float(val.replace('K', '')) * bsize
        return b_val
    if 'M' in val:
        b_val = float(val.replace('M', '')) * bsize * bsize
        return b_val


def parse_ram(files):
    res_max = dict()
    res_avg = dict()
    for file_name in files:
        sim_num, data_size, pub_num, sub_num, rand = file_name.split('/')[-1].split('_')
        data_size = int(re.sub("[^0-9]", "", data_size))
        pub_num = int(re.sub("[^0-9]", "", pub_num))

        if sim_num not in res_max:
            res_max[sim_num] = dict()
            res_avg[sim_num] = dict()

        if pub_num not in res_max[sim_num]:
            res_max[sim_num][pub_num] = dict()
            res_avg[sim_num][pub_num] = dict()

        with open(path + file_name) as f:
            lines = f.readlines()

        parse = [li.replace(' \x1b[2J\x1b[Hmosquitto-broker', '').replace(' /', '').split('\t') for li in
                 ''.join(lines).split('\n') if li]

        ram_results = [li[-1].split(' ')[0] for li in parse]
        byte_results = [to_bytes(v) for v in ram_results if v != '--']
        res_max[sim_num][pub_num][data_size] = round(max(byte_results))
        res_avg[sim_num][pub_num][data_size] = round(statistics.mean(byte_results))

        print(pub_num, data_size, '--> done')

    return res_max, res_avg


def parse_db(file):
    res = dict()
    for file_name in file:
        _, sim_num, data_size, pub_num, sub_num, rand = file_name.split('/')[-1].split('_')
        data_size = int(re.sub("[^0-9]", "", data_size))
        pub_num = int(re.sub("[^0-9]", "", pub_num))

        if sim_num not in res:
            res[sim_num] = dict()

        if pub_num not in res[sim_num]:
            res[sim_num][pub_num] = dict()

        with open(path + file_name) as f:
            lines = f.readlines()

        res[sim_num][pub_num][data_size] = to_bytes(''.join(lines).replace('\n', ''))
    return res

pre_path = "/Users/tugrul/Desktop/Tez/mixed_migration/"
path = pre_path+'results_50_75/'
only_ram = [f for f in listdir(path) if isfile(join(path, f)) if 'ls_' not in f if not f.startswith('.')]
only_ls = [f for f in listdir(path) if isfile(join(path, f)) if 'ls_' in f if not f.startswith('.')]


result_max, result_avg = parse_ram(only_ram)

print(result_avg)
print()
print(parse_db(only_ls))
