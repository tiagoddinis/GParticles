#version 430
#extension GL_ARB_compute_shader : enable
#extension GL_ARB_shader_storage_buffer_object : enable
#extension GL_ARB_compute_variable_group_size : enable

////////////////////////////////////////////////////////////////////////////////
// RESOURCES
////////////////////////////////////////////////////////////////////////////////

layout(binding = 0, offset = 0) uniform atomic_uint puddle_aliveParticles;
layout(binding = 1, offset = 0) uniform atomic_uint puddle_emissionAttempts;
layout(binding = 2, offset = 0) uniform atomic_uint randomCounter;

layout(std430, binding = 3) buffer Puddle_velocities
{
	vec4 puddle_velocities[];
};

layout(std430, binding = 4) buffer Puddle_floorHit
{
	float puddle_floorHit[];
};

layout(std430, binding = 5) buffer Puddle_lastPositions
{
	vec4 puddle_lastPositions[];
};

layout(std430, binding = 6) buffer Puddle_lifetimes
{
	float puddle_lifetimes[];
};

layout(std430, binding = 7) buffer Puddle_size
{
	float puddle_size[];
};

layout(std430, binding = 8) buffer Puddle_lineLifetime
{
	float puddle_lineLifetime[];
};

layout(std430, binding = 9) buffer Puddle_positions
{
	vec4 puddle_positions[];
};

layout(std430, binding = 10) buffer Puddle_colors
{
	vec4 puddle_colors[];
};

layout(std430, binding = 11) buffer Puddle_texCoords
{
	vec2 puddle_texCoords[];
};

layout(std430, binding = 12) buffer VirusPos
{
	vec4 virusPos[];
};

layout(local_size_variable) in;

uniform float puddle_maxParticles;
uniform float puddle_toCreate;
uniform float puddle_deltaTime;
uniform float virusAnimationRadius;
uniform float virusAnimationAngle;
uniform vec2 mouseXY;

uint gid = gl_GlobalInvocationID.x;

////////////////////////////////////////////////////////////////////////////////
// UTILITIES
////////////////////////////////////////////////////////////////////////////////

// Random Number Generation in range [-1,1]
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

float snoise(vec2 v) {
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
  	vec3 p = permute(permute( i.y + vec3(0.0, i1.y, 1.0 )) +
					 i.x + vec3(0.0, i1.x, 1.0 ));

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



// Returns a random float in the given range
////////////////////////////////////////////////////////////////////////////////
float randInRange(float minVal, float maxVal)
{
	float val = snoise(vec2(atomicCounterIncrement(randomCounter)));
	float percentage = val * 0.5 + 0.5;
	return mix(minVal, maxVal, percentage);
}



// Returns a vec2 with random components in the given range
////////////////////////////////////////////////////////////////////////////////
vec2 randInRangeV2(float minVal, float maxVal)
{
	return vec2(randInRange(minVal, maxVal),
				randInRange(minVal, maxVal));
}



// Returns a vec3 with random components in the given range
////////////////////////////////////////////////////////////////////////////////
vec3 randInRangeV3(float minVal, float maxVal)
{
	return vec3(randInRange(minVal, maxVal),
				randInRange(minVal, maxVal),
				randInRange(minVal, maxVal));
}



// Returns a matrix that describes the rotation around an arbitrary axis by the
// given angle in radians
////////////////////////////////////////////////////////////////////////////////
mat4 rotationMatrix(vec3 axis, float angle)
{
	axis = normalize(axis);
	float s = sin(angle);
	float c = cos(angle);
	float oc = 1.0 - c;
	
	return mat4(oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,  0.0,
				oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,  0.0,
				oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c,           0.0,
				0.0,                                0.0,                                0.0,                                1.0);
}



// Returns a matrix constructed from the given direction axis that holds the
// axis of a 3D space
////////////////////////////////////////////////////////////////////////////////
mat4 construct3DSpace(vec3 dir, bool flipRight, bool flipUp)
{
	dir = normalize(dir);
	vec3 right, up;

	if (flipRight)
	  right = normalize(cross(vec3(0, 1, 0), dir));
	else
	  right = normalize(cross(dir, vec3(0, 1, 0)));

	if (flipUp)
	  up = normalize(cross(right, dir));
	else
	  up = normalize(cross(dir, right));
	
	return mat4(vec4(right, 0),
				vec4(up, 0),
				vec4(dir, 0),
				vec4(0, 0, 0, 1));
}

////////////////////////////////////////////////////////////////////////////////
// EMISSION - requires: utilities.glsl
////////////////////////////////////////////////////////////////////////////////

// Returns particle position inside a cone primitive
////////////////////////////////////////////////////////////////////////////////
vec4 conePositionGenerator(float radius, float height, bool coneBaseIsOrigin,
						   bool positionsInVolume)
{
	// compute random y in range [0, height]
	float y = randInRange(0, 1);

	// compute particle horizontal distance from cone axis
	float newRadius = (radius * y) / height;
	float dist = newRadius;
	if (positionsInVolume)
	{
		dist = randInRange(0, newRadius);
	}

	// compute rotation angle (in degrees) around cone axis
	float angle = randInRange(0, 360);

	// calculate corresponding x and z polar coordinates
	float x = dist * sin(angle);
	float z = dist * cos(angle);

	// compute cone orientation
	y = (coneBaseIsOrigin) ? height - y : y;

	return vec4(x, y, z, 1);
}



// Returns particle position inside a sphere primitive
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




// Returns particle position from a plane primitive
////////////////////////////////////////////////////////////////////////////////
vec4 planePositionGenerator(float width, float height, bool centeredAtOrigin,
							bool horizontal)
{
	float minMultiplier = 0;
	float maxMultiplier = 1;
	if (centeredAtOrigin)
	{
		minMultiplier = 0.5;
		maxMultiplier = 0.5;
	}

	vec4 pos = vec4(0,0,0,1);

	pos.x = randInRange(-width * minMultiplier, width * maxMultiplier);
	pos.y = randInRange(-height * minMultiplier, height * maxMultiplier);

	if (horizontal)
		pos.zy = pos.yz;

	return pos;
}



// Returns velocity vector with magnitude = intensity
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



// Returns velocity vector with random magnitude (minInt < magnitude < maxInt)
////////////////////////////////////////////////////////////////////////////////
vec3 velocityGenerator(vec3 dir, vec3 randomize, float minInt, float maxInt)
{
	float intensity = randInRange(minInt, maxInt);

	return velocityGenerator(dir, randomize, intensity);
}

void update()
{
	puddle_velocities[gid].y -= 0.5 * puddle_deltaTime;
	puddle_positions[gid].xyz += puddle_velocities[gid].xyz * puddle_deltaTime;

	if (puddle_positions[gid].y < -4)
	{
		if (puddle_floorHit[gid] == 0)
			puddle_lifetimes[gid] = 1;
		puddle_positions[gid].y = -4;
		puddle_floorHit[gid] = 1.0;
	}
}

void collision()
{
	;
}

void main()
{
	// if particle is not alive
	if (puddle_lifetimes[gid] <= 0)
		return;

	// age particle
	puddle_lifetimes[gid] -= puddle_deltaTime;

	// if particle just died
	if (puddle_lifetimes[gid] <= 0)
	{
		puddle_lifetimes[gid] = -1;
		atomicCounterDecrement(puddle_aliveParticles);

		return;
	}
	
	update();

	collision();
}