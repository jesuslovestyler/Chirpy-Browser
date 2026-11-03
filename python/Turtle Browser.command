#!/bin/bash
# Turtle Browser launcher for Mac — double-click me.
cd "$(dirname "$0")"

if ! command -v python3 >/dev/null 2>&1; then
  echo "Turtle Browser needs Python 3, and this Mac could not find it."
  echo "Tell Noki this message and she will help sort it out."
  echo
  read -n 1 -s -r -p "Press any key to close this window."
  exit 1
fi

if ! python3 -c "import tkinter" >/dev/null 2>&1; then
  echo "Python is here, but its window toolkit (Tkinter) is missing,"
  echo "so the Turtle Browser window cannot open yet."
  echo "Tell Noki this message and she will help sort it out."
  echo
  read -n 1 -s -r -p "Press any key to close this window."
  exit 1
fi

python3 turtle_browser.py
STATUS=$?
if [ $STATUS -ne 0 ]; then
  echo
  echo "Turtle Browser closed with an error (code $STATUS)."
  echo "Tell Noki what this window says and she will help."
  read -n 1 -s -r -p "Press any key to close this window."
fi
