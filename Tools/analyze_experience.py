"""Summarize native-window workload logs; UI update intervals are not frame times."""
import argparse
import json
import math
import statistics
from pathlib import Path


def load(path):
    rows = [json.loads(line.split(' ', 1)[1]) for line in Path(path).read_text().splitlines()
            if line.startswith('EXPERIENCE_WORKLOAD ')]
    if len(rows) < 10 or any(sum(r['items'] == count for r in rows) < 5 for count in (100, 1000)):
        raise ValueError('At least five rounds for each workload are required')
    return rows


def summary(values):
    values = sorted(values)
    return {'median': statistics.median(values), 'p95': values[math.ceil(len(values) * .95) - 1], 'n': len(values)}


def compare(before, after):
    report = {}
    for count in (100, 1000):
        pairs = [[r for r in rows if r['items'] == count] for rows in (before, after)]
        operations = {}
        for name in pairs[0][0]['cpu_ms']:
            entry = {}
            for metric in ('samples_ms', 'cpu_ms'):
                values = [[v for row in rows for v in row[metric].get(name, [])] for rows in pairs]
                if not all(values):
                    continue
                a, b = map(summary, values)
                entry[metric] = {'before': a, 'after': b, 'median_delta': b['median'] - a['median'],
                    'p95_delta': b['p95'] - a['p95'],
                    'round_medians': [[statistics.median(row[metric][name]) for row in rows] for rows in pairs]}
            entry['resources'] = {}
            for key in ('interrupt_wakeups', 'package_idle_wakeups', 'disk_read_bytes', 'disk_write_bytes', 'footprint_bytes'):
                values = [[v[key] for row in rows for v in row['resources'].get(name, []) if key in v] for rows in pairs]
                if all(values):
                    entry['resources'][key] = dict(zip(('before', 'after'), map(summary, values)))
            operations[name] = entry
        report[count] = operations
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('before'); parser.add_argument('after'); parser.add_argument('output')
    args = parser.parse_args()
    Path(args.output).write_text(json.dumps(compare(load(args.before), load(args.after)), indent=2) + '\n')
