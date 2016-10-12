#!/bin/bash

psql -U postgres test -c "select urlencode('hello world');"
