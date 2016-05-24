////////////////////////////////////////////////////////////////////////////////
// FUNCTIONS
////////////////////////////////////////////////////////////////////////////////

// -- Utilities --
////////////////////////////////////////////////////////////////////////////////
// Description : Array and textureless GLSL 2D simplex noise function.
//      Author : Ian McEwan, Ashima Arts.
//  Maintainer : ijm
//     Lastmod : 20110822 (ijm)
//     License : Copyright (C) 2011 Ashima Arts. All rights reserved.
//               Distributed under the MIT License. See LICENSE file.
//               https://github.com/ashima/webgl-noise

vec3 mod289(vec3 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec2 mod289(vec2 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec3 permute(vec3 x) {
  return mod289(((x*34.0)+1.0)*x);
}

float snoise(vec2 v)
  {
  const vec4 C = vec4(0.211324865405187,  // (3.0-sqrt(3.0))/6.0
                      0.366025403784439,  // 0.5*(sqrt(3.0)-1.0)
                     -0.577350269189626,  // -1.0 + 2.0 * C.x
                      0.024390243902439); // 1.0 / 41.0
// First corner
  vec2 i  = floor(v + dot(v, C.yy) );
  vec2 x0 = v -   i + dot(i, C.xx);

// Other corners
  vec2 i1;
  //i1.x = step( x0.y, x0.x ); // x0.x > x0.y ? 1.0 : 0.0
  //i1.y = 1.0 - i1.x;
  i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  // x0 = x0 - 0.0 + 0.0 * C.xx ;
  // x1 = x0 - i1 + 1.0 * C.xx ;
  // x2 = x0 - 1.0 + 2.0 * C.xx ;
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;

// Permutations
  i = mod289(i); // Avoid truncation effects in permutation
  vec3 p = permute( permute( i.y + vec3(0.0, i1.y, 1.0 ))
		+ i.x + vec3(0.0, i1.x, 1.0 ));

  vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
  m = m*m ;
  m = m*m ;

// Gradients: 41 points uniformly over a line, mapped onto a diamond.
// The ring size 17*17 = 289 is close to a multiple of 41 (41*7 = 287)

  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;

// Normalise gradients implicitly by scaling m
// Approximation of: m *= inversesqrt( a0*a0 + h*h );
  m *= 1.79284291400159 - 0.85373472095314 * ( a0*a0 + h*h );

// Compute final noise value at P
  vec3 g;
  g.x  = a0.x  * x0.x  + h.x  * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}

float randInRange(float minVal, float maxVal)
{
	float val = snoise(vec2(atomicCounterIncrement(rocket_randomCounter)));
	float percentage = val * 0.5 + 0.5;
	return mix(minVal, maxVal, percentage);
}

float randInRange(vec2 seed, float minVal, float maxVal)
{
	float val = snoise(seed);
	float percentage = val * 0.5 + 0.5;
	return mix(minVal, maxVal, percentage);
}

vec2 randInRangeV2(vec2 seed, float minVal, float maxVal)
{
	return vec2(	randInRange(seed, minVal, maxVal),
					randInRange(vec2(seed.x, seed.y*seed.y), minVal, maxVal)
				);
}

vec3 randInRangeV3(vec2 seed, float minVal, float maxVal)
{
	return vec3(	randInRange(seed, minVal, maxVal),
					randInRange(vec2(seed.x, seed.y*seed.y), minVal, maxVal),
					randInRange(vec2(seed.x+3*seed.x, seed.y+45), minVal, maxVal)
				);
}


// -- Emission --
////////////////////////////////////////////////////////////////////////////////
vec4 conePositionGenerator(float radius, float height, bool coneBaseIsOrigin, bool positionsInVolume)
{
	// compute random y in range [0, height]
	float y = randInRange(vec2(gid, gid * gid), 0, 1);

	// compute particle horizontal distance from cone axis
	float newRadius = (radius * y) / height;
	float dist = newRadius;
	if (positionsInVolume)
	{
		dist = randInRange(vec2(gid + 3 , gid + 4 * gid), 0, newRadius);
	}

	// compute rotation angle (in degrees) around cone axis
	float angle = randInRange(vec2(gid+7,gid+8*gid) * 0.01, 0, 360);

	// calculate corresponding x and z polar coordinates
	float x = dist * sin(angle);
	float z = dist * cos(angle);

	// compute cone orientation
	y = (coneBaseIsOrigin) ? height - y : y;

	return vec4(x, y, z, 1);
}

////////////////////////////////////////////////////////////////////////////////
vec4 spherePositionGenerator(float maxRadius, bool positionsInVolume)
{
	float radius = maxRadius;
	if (positionsInVolume)
		radius = randInRange(0, maxRadius);

	// compute rotation angle (in degrees) around cone axis
	float angle = randInRange(0, 360);
	float angle2 = randInRange(0, 180);

	// calculate corresponding x and z polar coordinates
	float x = radius * sin(angle) * cos(angle2);
	float z = radius * cos(angle);
	float y = radius * sin(angle) * sin(angle2);

	return vec4(x, y, z, 1);
}

////////////////////////////////////////////////////////////////////////////////
vec3 velocityGenerator(vec3 dir, vec3 randomize, float intensity)
{
	vec3 vel = dir;

	// check if any direction should be randomized
	if (randomize.x > 0) vel.x = randInRange(-1,1);
	if (randomize.y > 0) vel.y = randInRange(-1,1);
	if (randomize.z > 0) vel.z = randInRange(-1,1);

	// avoid normalizing a zero vector
	if (vel != vec3(0)) vel = normalize(vel);

	return vel * intensity;
}

vec3 velocityGenerator(vec3 dir, vec3 randomize, float minInt, float maxInt)
{
	float intensity = randInRange(vec2(gid*gid,gid*gid), minInt, maxInt);

	return velocityGenerator(dir, randomize, intensity);
}

