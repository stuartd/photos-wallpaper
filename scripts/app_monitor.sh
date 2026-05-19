date
echo

echo "App support size:"
du -sh ~/Library/Application\ Support/photos-wallpaper
echo

echo "Files:"
ls -lh ~/Library/Application\ Support/photos-wallpaper
echo

echo "Wallpaper file count:"
find ~/Library/Application\ Support/photos-wallpaper \
  -name 'current-wallpaper-*.jpg' \
  -type f | wc -l
echo

echo "Wallpaper file total size:"
find ~/Library/Application\ Support/photos-wallpaper \
  -name 'current-wallpaper-*.jpg' \
  -type f \
  -exec du -ch {} + | tail -1
echo

echo "Macintosh HD free space:"
df -h /
