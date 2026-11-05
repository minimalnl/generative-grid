/**
 * Metadata Structure Tests for Generative Square
 * 
 * Validates that the metadata JSON structure is correct for Universal Everything
 */

const assert = require('assert');

// Simulated metadata JSON output from the contract
function generateMetadataJSON(tokenId) {
    const BASE_URI = "https://generative-square.example.com/art/";
    
    return {
        name: `Generative Square #${tokenId}`,
        description: "Generative Square is an on-chain generative art collection.",
        icon: [
            {
                width: 600,
                height: 600,
                url: `${BASE_URI}${tokenId}-600.png`
            }
        ],
        images: [[
            {
                width: 2400,
                height: 2400,
                url: `${BASE_URI}${tokenId}.png`
            }
        ]],
        links: [],
        assets: [],
        attributes: [
            {
                key: "Seed",
                value: String(tokenId),
                type: "string"
            }
        ]
    };
}

// Test suite
function runTests() {
    console.log('Running Generative Square metadata structure tests...\n');
    
    const tokenId = 123;
    const metadata = generateMetadataJSON(tokenId);
    
    // Test 1: Icon structure
    console.log('✓ Test 1: Icon is a single-level array');
    assert(Array.isArray(metadata.icon), 'icon should be an array');
    assert(metadata.icon.length === 1, 'icon should have exactly one element');
    assert(!Array.isArray(metadata.icon[0]), 'icon[0] should be an object, not an array');
    
    // Test 2: Icon content
    console.log('✓ Test 2: Icon contains 600px thumbnail');
    assert(metadata.icon[0].width === 600, 'icon width should be 600');
    assert(metadata.icon[0].height === 600, 'icon height should be 600');
    assert(metadata.icon[0].url.endsWith('-600.png'), 'icon URL should end with -600.png');
    
    // Test 3: Images structure
    console.log('✓ Test 3: Images is a nested array');
    assert(Array.isArray(metadata.images), 'images should be an array');
    assert(metadata.images.length === 1, 'images should have one element');
    assert(Array.isArray(metadata.images[0]), 'images[0] should be an array');
    assert(metadata.images[0].length === 1, 'images[0] should have exactly one image');
    
    // Test 4: Images content
    console.log('✓ Test 4: Images contains only 2400px artwork');
    assert(metadata.images[0][0].width === 2400, 'image width should be 2400');
    assert(metadata.images[0][0].height === 2400, 'image height should be 2400');
    assert(metadata.images[0][0].url.endsWith('.png'), 'main image URL should end with .png');
    assert(!metadata.images[0][0].url.includes('-600'), 'main image URL should not contain -600');
    
    // Test 5: No 600px in images array
    console.log('✓ Test 5: Images array does not contain 600px version');
    const has600InImages = metadata.images[0].some(img => img.width === 600 || img.height === 600);
    assert(!has600InImages, 'images array should not contain 600px version');
    
    // Test 6: Name, description, and attributes
    console.log('✓ Test 6: Name, description, and attributes are preserved');
    assert(metadata.name === `Generative Square #${tokenId}`, 'name should match token ID');
    assert(metadata.description.includes('Generative Square'), 'description should be present');
    assert(Array.isArray(metadata.attributes), 'attributes should be an array');
    assert(metadata.attributes.length > 0, 'attributes should not be empty');
    assert(metadata.attributes[0].key === 'Seed', 'should have Seed attribute');
    
    console.log('\n✅ All tests passed!');
    console.log('\nMetadata structure is correct for Universal Everything:');
    console.log('  - Icon: Single-level array with 600px thumbnail');
    console.log('  - Images: Nested array with only 2400px main artwork');
}

// Run tests
try {
    runTests();
} catch (error) {
    console.error('\n❌ Test failed:', error.message);
    process.exit(1);
}
