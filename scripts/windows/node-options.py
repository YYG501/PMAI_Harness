"""Translate explicit Node preload paths without evaluating NODE_OPTIONS."""
import json
import os
import shlex
import subprocess

arguments = shlex.split(os.environ['NODE_OPTIONS'])
path_next = False
for index, argument in enumerate(arguments):
    prefix, separator, value = argument.partition('=')
    if path_next:
        value, prefix, separator = argument, '', ''
    if path_next or (separator and prefix in ('--require', '--import')):
        if value.startswith('/'):
            value = subprocess.check_output(['cygpath', '-m', value], text=True).strip()
        arguments[index] = prefix + separator + value
    path_next = argument in ('--require', '-r', '--import')
print(' '.join(json.dumps(argument, ensure_ascii=False) for argument in arguments))
