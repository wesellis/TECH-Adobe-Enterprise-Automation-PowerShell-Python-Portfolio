#!/usr/bin/env python3
"""
BASIC LEVEL: Simple license check
Learning: Python basics, simple logic, basic reporting
"""

def check_license_usage(total_licenses, used_licenses):
    """Basic license check function"""
    available = total_licenses - used_licenses
    usage_percent = (used_licenses / total_licenses) * 100

    print(f"License Usage Report")
    print(f"=" * 30)
    print(f"Total Licenses: {total_licenses}")
    print(f"Used Licenses: {used_licenses}")
    print(f"Available: {available}")
    print(f"Usage: {usage_percent:.1f}%")

    # Simple logic
    if usage_percent > 90:
        print("\n⚠️ WARNING: High license usage!")
    elif usage_percent > 80:
        print("\n📊 Note: License usage above 80%")
    else:
        print("\n✅ License usage is healthy")

    return available

# Basic execution
if __name__ == "__main__":
    # Simple hardcoded values
    total = 100
    used = 75

    available_licenses = check_license_usage(total, used)
    print(f"\nYou can provision {available_licenses} more users")