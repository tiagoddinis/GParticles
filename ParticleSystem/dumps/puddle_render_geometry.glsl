#version 430

////////////////////////////////////////////////////////////////////////////////
// RESOURCES
////////////////////////////////////////////////////////////////////////////////

layout(binding = 1, offset = 0) uniform atomic_uint randomCounter;
layout(binding = 2, offset = 0) uniform atomic_uint puddle_aliveParticles;
layout(binding = 3, offset = 0) uniform atomic_uint puddle_emissionAttempts;

in float puddle_floorHitV[];
in vec4 puddle_lastPositionsV[];
in float puddle_lifetimesV[];
in float puddle_sizeV[];
in float puddle_lineLifetimeV[];
in vec4 puddle_colorsV[];
in vec4 puddle_positionsV[];
in vec2 puddle_texCoordsV[];
in vec4 puddle_velocitiesV[];
in vec4 virusPosV[];

out float puddle_floorHitG;
out vec4 puddle_lastPositionsG;
out float puddle_lifetimesG;
out float puddle_sizeG;
out float puddle_lineLifetimeG;
out vec4 puddle_colorsG;
out vec4 puddle_positionsG;
out vec2 puddle_texCoordsG;
out vec4 puddle_velocitiesG;
out vec4 virusPosG;
uniform mat4 model, view, projection;

uniform float virusAnimationAngle;
uniform vec2 mouseXY;
uniform float puddle_maxParticles;
uniform float puddle_toCreate;
uniform float puddle_deltaTime;
uniform float virusAnimationRadius;

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
// BILLBOARD - requires: utilities.glsl
////////////////////////////////////////////////////////////////////////////////

// Returns new quad coordinates vector so they always face the XZ plane
////////////////////////////////////////////////////////////////////////////////
vec4[4] billboardFaceXZ(vec4[4] quad, mat4 viewModel)
{
    for (int i = 0; i < 4; i++)
    {
        quad[i].yz = quad[i].zy;
        quad[i] = viewModel * quad[i];
    }
    
    return quad;
}



// Returns new quad coordinates vector so they face the camera while also
// aligning with the moving direction
////////////////////////////////////////////////////////////////////////////////
vec4[4] billboardDirectionCamera(vec4[4] quad, vec3 dir, vec3 particleToCamera)
{
    dir = normalize(dir);
    particleToCamera = normalize(particleToCamera);
    vec3 up = normalize(cross(dir, particleToCamera));
    vec3 right = normalize(cross(up, dir));
    mat4 orientation = mat4(vec4(dir, 0),
                            vec4(up, 0),
                            vec4(right, 0),
                            vec4(0, 0, 0, 1));
    
    for (int i = 0; i < 4; i++)
        quad[i] =  orientation * quad[i];

    return quad;
}



// Returns new quad coordinates vector so they always face the moving direction
////////////////////////////////////////////////////////////////////////////////
vec4[4] billboardDirection(vec4[4] quad, vec3 dir)
{
    mat4 orientation = construct3DSpace(dir, false, false);

    for (int i = 0; i < 4; i++)
        quad[i] =  orientation * quad[i];

    return quad;
}



// Returns new quad coordinates vector so they always face the up axis of the
// moving direction
////////////////////////////////////////////////////////////////////////////////
vec4[4] billboardDirectionUp(vec4[4] quad, vec3 dir)
{
    mat4 orientation = construct3DSpace(dir, false, false);

    vec4 tmp = orientation[1];
    orientation[1] = orientation[2];
    orientation[2] = tmp;

    for (int i = 0; i < 4; i++)
        quad[i] =  orientation * quad[i];

    return quad;
}



// Returns new quad coordinates vector so they always face the right axis of the
// moving direction
////////////////////////////////////////////////////////////////////////////////
vec4[4] billboardDirectionRight(vec4[4] quad, vec3 dir)
{
    mat4 orientation = construct3DSpace(dir, false, false);
    
    vec4 tmp = orientation[0];
    orientation[0] = orientation[2];
    orientation[2] = tmp;

    for (int i = 0; i < 4; i++)
        quad[i] =  orientation * quad[i];

    return quad;
}



// Returns a quad coordinates vector with the given edgeSize
////////////////////////////////////////////////////////////////////////////////
vec4[4] getQuad(float width, float height)
{
    float X = width * 0.5;
    float Y = height * 0.5;

    vec4 quad[4] = {vec4(-X,-Y,0,0),
                    vec4(-X, Y, 0, 0),
                    vec4(X, -Y, 0, 0),
                    vec4(X, Y, 0, 0)};

    return quad;
}



// Returns new stretched quad coordinates vector
////////////////////////////////////////////////////////////////////////////////
vec4[4] getStretchedQuad(float width, float height, vec3 velocity, bool horizontal, float deltaT)
{
    float ratio = clamp(length(velocity), 1.0, 2.0);

    float X = (width * 0.5) * ratio;
    float Y = (height * 0.5) / ratio;

    vec4 quad[4] = {vec4(-X,-Y,0,0),
                    vec4(-X, Y, 0, 0),
                    vec4(X, -Y, 0, 0),
                    vec4(X, Y, 0, 0)};

    if (horizontal)
    {
        for (int i = 0; i < 4; i++)
        {
            quad[i].xy = quad[i].yx;
        }
    }

    return quad;
}



layout(points) in;
layout(triangle_strip, max_vertices=4) out;

void main()
{	
    puddle_lifetimesG = puddle_lifetimesV[0];
    puddle_colorsG = puddle_colorsV[0];

    vec4 quad[4];

    if (puddle_floorHitV[0] == 1)
    {
        // puddle_lifetimesG starts at 1 so we'll a puddle with size 0.2 for a
        // brief moment and then we shrink it until it is gone
        float edgeSize = min(puddle_lifetimesG/4, 0.2);

        quad = getQuad(edgeSize, edgeSize);
        quad = billboardFaceXZ(quad, view * model);
    }
    else
    {
        quad = getStretchedQuad(0.1, 0.1, puddle_velocitiesV[0].xyz, false, puddle_deltaTime);
        quad = billboardDirectionCamera(quad,
                                        (view*model*puddle_velocitiesV[0]).xyz,
                                        -vec3(gl_in[0].gl_Position.xyz));
    }

    // generate final vertex positions
    gl_Position = projection * (gl_in[0].gl_Position + quad[0]);
    puddle_texCoordsG = vec2(0,0);
    EmitVertex();

    gl_Position = projection * (gl_in[0].gl_Position + quad[1]);
    puddle_texCoordsG = vec2(0,1);
    EmitVertex();

    gl_Position = projection * (gl_in[0].gl_Position + quad[2]);
    puddle_texCoordsG = vec2(1,0);
    EmitVertex();

    gl_Position = projection * (gl_in[0].gl_Position + quad[3]);
    puddle_texCoordsG = vec2(1,1);
    EmitVertex();

    EndPrimitive();
}  

