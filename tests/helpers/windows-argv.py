"""Fixture for the PowerShell argv/exit-code boundary."""
import json
import os
import sys
value = {'argv': sys.argv[2:], 'stdin': sys.stdin.read()} if sys.argv[1:2] == ['--stdin-json'] else sys.argv[1:]
print(json.dumps(value, ensure_ascii=False))
raise SystemExit(int(os.environ.get('PMAI_TEST_ARGV_EXIT', '0')))
