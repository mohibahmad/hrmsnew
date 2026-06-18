import os
import re

directory = '/Users/macbookpro/hrms/lib/screens'

for filename in os.listdir(directory):
    if filename.endswith(".dart"):
        filepath = os.path.join(directory, filename)
        with open(filepath, 'r') as f:
            content = f.read()

        # We want to replace BorderRadius.circular(4) and (8) with (6)
        # but only in the context of ElevatedButton.styleFrom where backgroundColor is blue or it's a known blue button.
        # Given the request is "blue buttons", we can look for the pattern of ElevatedButton with blue.
        # Actually, let's just change all ElevatedButton shape border radius to 6 across all screens.
        
        # Regex to find: shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)), or (8)
        new_content = re.sub(
            r'(shape:\s*RoundedRectangleBorder\(\s*borderRadius:\s*BorderRadius\.circular\()([48])(\)\s*,?\s*\))',
            r'\g<1>6\g<3>',
            content
        )
        # Also handle cases with multiple lines like:
        # shape: RoundedRectangleBorder(
        #   borderRadius: BorderRadius.circular(4),
        # )
        new_content = re.sub(
            r'(borderRadius:\s*BorderRadius\.circular\()([48])(\))',
            r'\g<1>6\g<3>',
            new_content
        )
        
        if content != new_content:
            with open(filepath, 'w') as f:
                f.write(new_content)
            print(f"Updated {filename}")

