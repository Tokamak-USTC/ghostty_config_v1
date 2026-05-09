// Configuration
#define ZOOM_DURATION 0.65
#define MAX_SCALE 1.75

float easeOutCubic(float t) {
    return 1.0 - pow(1.0 - t, 3.0);
}

// 2D Random
float random (in vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

float noise(in vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);

    float a = random(i);
    float b = random(i + vec2(1.0, 0.0));
    float c = random(i + vec2(0.0, 1.0));
    float d = random(i + vec2(1.0, 1.0));

    vec2 u = f * f * (3.0 - 2.0 * f);

    return mix(a, b, u.x) +
           (c - a) * u.y * (1.0 - u.x) +
           (d - b) * u.x * u.y;
}

float fbm(in vec2 st) {
    float value = 0.0;
    float amplitude = 0.5;

    for (int i = 0; i < 5; i++) {
        value += amplitude * noise(st);
        st = st * 2.0 + vec2(13.1, 7.7);
        amplitude *= 0.5;
    }

    return value;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord.xy / iResolution.xy;
    
    // Default background
    vec4 bgColor = texture(iChannel0, uv);
    fragColor = bgColor;
    
    float timeSinceChange = iTime - iTimeCursorChange;
    
    // Only run effect during the duration
    if (timeSinceChange < 0.0 || timeSinceChange > ZOOM_DURATION) {
        return;
    }
    
    float moveX = iCurrentCursor.x - iPreviousCursor.x;
    float moveY = iCurrentCursor.y - iPreviousCursor.y;
    
    // Only animate on horizontal movement
    if (abs(moveY) > 1.0) return;
    
    float charWidth = abs(moveX);
    if (charWidth < 2.0) return;

    float progress = timeSinceChange / ZOOM_DURATION;
    float intensity = 1.0 - easeOutCubic(progress); // Strong at start, fades out
    
    // Calculate center of the previous character
    float centerX = (iPreviousCursor.x + iCurrentCursor.x) * 0.5;
    float centerY = iPreviousCursor.y - iPreviousCursor.w * 0.5; 
    
    vec2 centerPos = vec2(centerX, centerY);
    vec2 targetSize = vec2(charWidth, iPreviousCursor.w);
    
    // Lens/Crop area
    vec2 zoomSize = targetSize * 0.9; // Slightly smaller to avoid edges
    
    vec2 cursorUVMin = (centerPos - zoomSize * 0.5) / iResolution.xy;
    vec2 cursorUVMax = (centerPos + zoomSize * 0.5) / iResolution.xy;
    vec2 cursorCenter = (cursorUVMin + cursorUVMax) * 0.5;
    
    // Scale effect
    //float scale = 1.0;
    float scale = 1.0 + easeOutCubic(progress) * (MAX_SCALE - 1.0);

    
    float lensHeight = cursorUVMax.y - cursorUVMin.y;
    float lensWidth = cursorUVMax.x - cursorUVMin.x;
    float sliceCount = 7.0;
    float timeStep = floor(iTime * 18.0);

    // Base Source UV (where we look in the texture)
    vec2 sourceUV = cursorCenter + (uv - cursorCenter) / scale;
    vec2 localUV = (sourceUV - cursorUVMin) / vec2(lensWidth, lensHeight);

    bool insideBaseLens = localUV.x >= 0.0 && localUV.x <= 1.0 &&
                          localUV.y >= 0.0 && localUV.y <= 1.0;

    if (insideBaseLens) {
        float sliceIndex = floor(localUV.y * sliceCount);
        float edgeNoiseL = fbm(vec2(sliceIndex * 0.9, timeStep * 0.45 + 3.0));
        float edgeNoiseR = fbm(vec2(sliceIndex * 1.2, timeStep * 0.45 + 19.0));
        float edgeBurstL = random(vec2(sliceIndex, timeStep + 41.0));
        float edgeBurstR = random(vec2(sliceIndex + 17.0, timeStep + 59.0));
        float leftEdge = -0.10 + floor(edgeNoiseL * 4.0) * 0.11 * intensity;
        float rightEdge = 1.10 - floor(edgeNoiseR * 4.0) * 0.11 * intensity;
        if (edgeBurstL > 0.76) {
            leftEdge += 0.24 * intensity;
        }
        if (edgeBurstR > 0.76) {
            rightEdge -= 0.24 * intensity;
        }

        vec2 maskBlockGrid = vec2(max(2.0, floor(charWidth * 0.10)), 2.0);
        vec2 maskBlockCoord = floor(localUV * maskBlockGrid);
        float maskNoise = fbm(maskBlockCoord * 0.7 + vec2(timeStep * 0.25, 23.0));
        float chipNoise = random(maskBlockCoord + vec2(timeStep, 73.0));
        bool missingChunk = maskNoise > (0.90 - 0.14 * intensity) || chipNoise > (0.985 - 0.05 * intensity);

        float cutBand = floor(localUV.y * 3.0);
        float cutNoise = random(vec2(cutBand, timeStep + 101.0));
        if (cutNoise > 0.82) {
            float cutStart = 0.18 + random(vec2(cutBand, timeStep + 7.0)) * 0.34;
            float cutWidth = 0.22 + random(vec2(cutBand, timeStep + 13.0)) * 0.30;
            if (localUV.x > cutStart && localUV.x < cutStart + cutWidth) {
                missingChunk = true;
            }
        }

        bool insideLens = localUV.x >= leftEdge && localUV.x <= rightEdge && !missingChunk;
        if (!insideLens) {
            return;
        }

        // --- CRAZY EFFECTS START HERE ---
        
        // 1. Fractal slice offset
        float sliceNoise = fbm(vec2(sliceIndex * 1.7, timeStep));
        float sliceShift = (floor(sliceNoise * 7.0) - 3.0) / iResolution.x;
        vec2 distortedUV = sourceUV + vec2(sliceShift * 22.0 * intensity, 0.0);

        // 2. Blocky macroblocks
        vec2 blockGrid = vec2(max(2.0, floor(charWidth * 0.35)), 3.0);
        vec2 blockCoord = floor((distortedUV - cursorUVMin) / vec2(lensWidth, lensHeight) * blockGrid);
        float blockNoise = fbm(blockCoord + vec2(timeStep * 0.6, 11.0));
        float blockShift = (floor(blockNoise * 5.0) - 2.0) * 14.0 / iResolution.x;
        distortedUV.x += blockShift * intensity;

        // 3. Occasional line skipping
        float skipNoise = random(vec2(sliceIndex + timeStep, blockCoord.x));
        if (skipNoise > 0.82) {
            float jump = sign(skipNoise - 0.91) * lensHeight / sliceCount;
            distortedUV.y += jump * 1.35 * intensity;
        }

        // 4. Discrete RGB channel offsets
        float rgbNoise = fbm(vec2(sliceIndex * 0.9, blockCoord.x + timeStep * 0.4));
        float rgbStep = (floor(rgbNoise * 5.0) - 2.0) * 12.0 / iResolution.x * intensity;
        float r = texture(iChannel0, distortedUV + vec2(rgbStep, 0.0)).r;
        float g = texture(iChannel0, distortedUV).g;
        float b = texture(iChannel0, distortedUV - vec2(rgbStep * 1.4, 0.0)).b;
        
        vec3 finalColor = vec3(r, g, b);
        finalColor *= vec3(1.08, 1.0, 1.12);
        finalColor = min(finalColor, 1.0);
        
        // 5. Color Cycling / Inversion Pulse
        // Rapidly invert or shift colors at the peak of the animation
        float flash = sin(progress * 18.0) * 0.5 + 0.5;
        if (intensity > 0.45) {
             finalColor = mix(finalColor, 1.0 - finalColor, flash * 0.3);
        }
        
        // 6. Glitch / Noise lines
        float noise = random(vec2(sliceIndex, floor(iTime * 24.0)));
        if (noise > 0.93) {
            finalColor += vec3(0.18, 0.12, 0.28); // Neon-ish glitch lines
            // Horizontal shift for glitch
            finalColor.r = texture(iChannel0, distortedUV + vec2(0.04, 0.0)).r;
        }

        fragColor = mix(fragColor, vec4(finalColor, 1.0), intensity * 0.85);
    }
}
