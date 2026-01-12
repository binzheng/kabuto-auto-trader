#!/usr/bin/env python3
"""
Clear all cooldown keys from Redis for testing
"""
import redis

# Connect to Redis
r = redis.Redis(host='localhost', port=6379, db=0, decode_responses=True)

# Find all cooldown keys
cooldown_keys = r.keys("cooldown:*")

if cooldown_keys:
    print(f"Found {len(cooldown_keys)} cooldown keys:")
    for key in cooldown_keys:
        print(f"  - {key}")

    # Delete all cooldown keys
    deleted = r.delete(*cooldown_keys)
    print(f"\nDeleted {deleted} cooldown keys")
else:
    print("No cooldown keys found")

print("\nCooldown cleared successfully!")
