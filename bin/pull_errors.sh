#!/bin/bash
grep -B2 -A1 'ERROR' logs/scheduler-pull.log
