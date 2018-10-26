# Finds 10 largest directories and files on single disk mount.

# First cd into desired mount.
# E.g.: cd /
du -ax ./ 2> /dev/null | sort -n -r | head -n 10 | awk '{print $2}' | xargs -n 1 du -sh 2> /dev/null
