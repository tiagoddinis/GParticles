
out vec3 lightDirV;

void main()
{
	vec3 dir = normalize((@positions - @lastPositions).xyz);
	mat4 newModel = construct3DSpace(dir, true, false);
	mat4 modelRot = rotationMatrix(vec3(1,0,0) , radians(90));

    gl_Position = projection * view * (newModel * modelRot * vec4(vertexPosition.xyz, 0.0f) + model * @positions);
    @colorsV = @colors;

    vertexNormalV = normalize(  mat3(transpose(inverse(view * model))) * mat3(newModel) * mat3(modelRot)* vertexNormal);
	lightDirV = normalize(vec3(view *vec4(1,0.2,0.5,0)));
}