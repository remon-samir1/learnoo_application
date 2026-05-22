import re
import os

# Read the kernel blob
with open('apk_extracted/app_debug/assets/flutter_assets/kernel_blob.bin', 'rb') as f:
    content = f.read().decode('utf-8', errors='ignore')

# Find all Dart file references
pattern = r'file:///D:/projects/Remon/Learnoo/([^\s"<>|]+\.dart)'
matches = re.findall(pattern, content)
unique_files = sorted(set(matches))

print(f'Found {len(unique_files)} Dart source files')

# Save file list
os.makedirs('restored', exist_ok=True)
with open('restored/dart_source_file_list.txt', 'w') as f:
    for file in unique_files:
        f.write(file + '\n')

# Print the files
for file in unique_files:
    print(file)
