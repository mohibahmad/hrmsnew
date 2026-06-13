import os
import re

directory = 'lib/screens'

for root, _, files in os.walk(directory):
    for file in files:
        if file.endswith('.dart'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r') as f:
                content = f.read()
            
            # Change BorderRadius.circular(X) to 4 inside shape: RoundedRectangleBorder(...)
            # We'll use a somewhat generic regex that targets BorderRadius.circular(\d+)
            # but only if it's part of a dropdown.
            # Let's just find PopupMenuButton and DropdownButton and replace their radii.
            # Actually, reducing all BorderRadius.circular(12) or 8 to 4 inside PopupMenuButton is tricky without a parser.
            
            # Since PopupMenuButton is the main target, let's find PopupMenuButton instances and adjust them.
            # A simpler way: we'll find "PopupMenuButton" and "DropdownButton", then replace their properties.
            
            # Replacing border radius inside RoundedRectangleBorder for PopupMenuButton:
            new_content = re.sub(r'(shape:\s*RoundedRectangleBorder\s*\([^)]*?borderRadius:\s*BorderRadius\.circular\()\d+(\))', r'\g<1>4\g<2>', content)
            
            # Add color: Colors.white to PopupMenuButton if not present
            def add_color(match):
                body = match.group(0)
                if 'color:' not in body:
                    # Insert color: Colors.white, right after PopupMenuButton<String>( or PopupMenuButton(
                    return body.replace('(', '(\ncolor: Colors.white,', 1)
                return body
            
            # This is a bit hacky, so let's just do it manually for the files we found, or use a more targeted replacement.
