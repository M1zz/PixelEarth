#!/usr/bin/env python3
"""Nael bundle (Tools/source_art/nael): the planet's own sky, horizon and small creatures.

Usage: import_nael.py [OUT_DIR]     Runs last from import_assets.py. Files already match the game sizes, so they are copied as is.
"""
import os, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'source_art', 'nael')
OUT = os.path.join(HERE, '..', 'Sources', 'PixelEarth', 'Resources')

# source name -> game name
FILES = {'stars.png': 'stars.png', 'slimes.png': 'slimes.png', 'bat.png': 'bat.png',
         'horizon_distant.png': 'mountains0.png', 'horizon_near.png': 'mountains1.png'}

def main():
    for src, dst in FILES.items():
        shutil.copyfile(os.path.join(SRC, src), os.path.join(OUT, dst))
        print('nael:', src, '->', dst)

if __name__ == '__main__':
    if len(sys.argv) > 1: OUT = sys.argv[1]
    main()
