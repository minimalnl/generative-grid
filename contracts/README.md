# Generative Square Contracts

This directory contains the Solidity contracts for the Generative Square NFT project.

## Live Deployment

- **Mainnet Contract**: `0x33Dd4D3da812e2cc1B3692456470DFDD99659e62`
- **Network**: LUKSO Mainnet

⚠️ **IMPORTANT**: The live contract is already deployed and immutable. This repository serves as the source-of-truth for documentation and any future deployments.

## Metadata Structure

The contract generates LSP8 compatible metadata JSON with the following structure optimized for Universal Everything:

### Icon Field
The `icon` field contains a **single-level array** of image objects representing the 600x600 thumbnail:

```json
"icon": [
  {
    "width": 600,
    "height": 600,
    "url": "https://generative-square.example.com/art/N-600.png"
  }
]
```

### Images Field
The `images` field contains a **nested array** with only the main 2400x2400 artwork:

```json
"images": [[
  {
    "width": 2400,
    "height": 2400,
    "url": "https://generative-square.example.com/art/N.png"
  }
]]
```

### Complete Metadata Example

```json
{
  "name": "Generative Square #123",
  "description": "Generative Square is an on-chain generative art collection.",
  "icon": [
    {
      "width": 600,
      "height": 600,
      "url": "https://generative-square.example.com/art/123-600.png"
    }
  ],
  "images": [[
    {
      "width": 2400,
      "height": 2400,
      "url": "https://generative-square.example.com/art/123.png"
    }
  ]],
  "links": [],
  "assets": [],
  "attributes": [
    {
      "key": "Seed",
      "value": "123",
      "type": "string"
    }
  ]
}
```

## Image Assets

Each token has two associated image files:
- `{tokenId}.png` - 2400×2400px main artwork (used in `images`)
- `{tokenId}-600.png` - 600×600px thumbnail (used in `icon`)

## Changes from Previous Version

**Previous structure** (incorrect for Universal Everything):
- `"icon": []` (empty)
- `"images": [[{2400px}, {600px}]]` (both sizes in images array)

**New structure** (correct):
- `"icon": [{600px}]` (single-level array with thumbnail)
- `"images": [[{2400px}]]` (only main artwork)

This ensures Universal Everything properly treats the 2400px version as the main artwork and the 600px version as the icon/thumbnail only.

## Security Notes

⚠️ **Never transfer ownership to**: `0x7070b7Cb8fAe99B6C7DDd0eaBe831DCb6c3047FD`
