#!/usr/bin/env python3
"""
Create a simplified PNG icon based on the SVG nautical theme
"""

from PIL import Image, ImageDraw
import os

def create_nautical_icon():
    """Create a nautical-themed icon based on the SVG colors and design"""
    
    # Colors from the SVG (extracted from the path fills)
    navy_blue = (1, 57, 111)      # #01396F
    dark_blue = (12, 33, 91)      # #0C215B  
    darker_blue = (8, 28, 87)     # #081C57
    white = (252, 252, 253)       # #FCFCFD
    
    # Create high resolution image
    size = 1024
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Create a nautical compass-like design
    center = size // 2
    
    # Background circle (navy blue)
    outer_radius = size // 2 - 20
    draw.ellipse([center - outer_radius, center - outer_radius, 
                  center + outer_radius, center + outer_radius], 
                 fill=navy_blue + (255,))
    
    # Inner circle (darker blue)
    inner_radius = outer_radius - 60
    draw.ellipse([center - inner_radius, center - inner_radius,
                  center + inner_radius, center + inner_radius], 
                 fill=darker_blue + (255,))
    
    # Compass points (white)
    compass_radius = inner_radius - 40
    
    # North point (triangle)
    north_points = [
        (center, center - compass_radius),
        (center - 30, center - compass_radius + 80),
        (center + 30, center - compass_radius + 80)
    ]
    draw.polygon(north_points, fill=white + (255,))
    
    # South point (triangle)
    south_points = [
        (center, center + compass_radius),
        (center - 30, center + compass_radius - 80),
        (center + 30, center + compass_radius - 80)
    ]
    draw.polygon(south_points, fill=white + (255,))
    
    # East point (triangle)
    east_points = [
        (center + compass_radius, center),
        (center + compass_radius - 80, center - 30),
        (center + compass_radius - 80, center + 30)
    ]
    draw.polygon(east_points, fill=white + (255,))
    
    # West point (triangle)  
    west_points = [
        (center - compass_radius, center),
        (center - compass_radius + 80, center - 30),
        (center - compass_radius + 80, center + 30)
    ]
    draw.polygon(west_points, fill=white + (255,))
    
    # Center circle (white)
    center_radius = 40
    draw.ellipse([center - center_radius, center - center_radius,
                  center + center_radius, center + center_radius], 
                 fill=white + (255,))
    
    # Small center dot (navy blue)
    dot_radius = 15
    draw.ellipse([center - dot_radius, center - dot_radius,
                  center + dot_radius, center + dot_radius], 
                 fill=navy_blue + (255,))
    
    # Save the icon
    output_path = "assets/icons/app_icon.png"
    img.save(output_path, "PNG")
    print(f"Created nautical compass icon: {output_path}")
    
    return True

if __name__ == "__main__":
    try:
        create_nautical_icon()
        print("Icon creation successful!")
    except Exception as e:
        print(f"Error creating icon: {e}")
        exit(1)