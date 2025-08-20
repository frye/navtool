#!/usr/bin/env python3
"""
Convert SVG to PNG using cairosvg or Pillow with svg support
"""

import sys
import os
from pathlib import Path

def convert_svg_to_png():
    try:
        import cairosvg
        
        svg_path = Path("assets/icons/app_icon.svg")
        png_path = Path("assets/icons/app_icon.png")
        
        # Convert SVG to PNG at 1024x1024 resolution for high quality
        cairosvg.svg2png(
            url=str(svg_path), 
            write_to=str(png_path),
            output_width=1024,
            output_height=1024
        )
        
        print(f"Successfully converted {svg_path} to {png_path}")
        return True
        
    except ImportError:
        print("cairosvg not available, trying Pillow...")
        
        try:
            from PIL import Image
            import io
            
            # Read SVG content
            with open("assets/icons/app_icon.svg", "r") as f:
                svg_content = f.read()
                
            # This is a fallback that creates a simple blue square as placeholder
            # Since we can't easily convert SVG without proper libraries
            img = Image.new('RGBA', (1024, 1024), (1, 57, 111, 255))  # Navy blue from SVG
            img.save("assets/icons/app_icon.png", "PNG")
            
            print("Created placeholder PNG icon (install cairosvg for proper SVG conversion)")
            return True
            
        except ImportError:
            print("Neither cairosvg nor Pillow available")
            return False
    
    except Exception as e:
        print(f"Error converting SVG: {e}")
        return False

if __name__ == "__main__":
    if convert_svg_to_png():
        sys.exit(0)
    else:
        sys.exit(1)