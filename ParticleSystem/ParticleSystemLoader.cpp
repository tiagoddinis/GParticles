#include "ParticleSystemLoader.h"


bufferUmap ParticleSystemLoader::bufferHandles;
atomicUmap ParticleSystemLoader::atomicHandles;
uniformUmap ParticleSystemLoader::uniformHandles;


bool ParticleSystemLoader::loadProject(std::string filePath, std::vector<ParticleSystem> &psContainer)
{
	// open file and get first element handle
	TiXmlDocument doc(filePath);
	if (!doc.LoadFile())
	{
		printf("Failed to load file \"%s\"\n", doc);
		return false;
	}

	TiXmlHandle docHandle(&doc);
	TiXmlElement* projectElement = docHandle.FirstChildElement("project").ToElement();
	

	// initialize project resources
	TiXmlElement* resourcesElement = projectElement->FirstChildElement("resources");
	if (!loadBuffers(resourcesElement->FirstChildElement("buffers")))
	{
		printf("Unable to initialize buffers!\n");
		return false;
	}

	if (!loadAtomics(resourcesElement->FirstChildElement("atomics")))
	{
		printf("Unable to initialize atomics!\n");
		return false;
	}

	if (!loadUniforms(resourcesElement->FirstChildElement("uniforms")))
	{
		printf("Unable to initialize uniforms!\n");
		return false;
	}


	// load particle systems
	TiXmlElement* psystemElement = projectElement->FirstChildElement("psystem");
	for (; psystemElement; psystemElement = psystemElement->NextSiblingElement())
	{
		psContainer.push_back(loadParticleSystem(psystemElement));
	}
}


///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
ParticleSystem ParticleSystemLoader::loadParticleSystem(TiXmlElement* psystemElement)
{
	// load emitter
	ComputeProgram emitter;
	if (!loadComputeProgram(psystemElement->FirstChildElement("emitter"), emitter))
	{
		printf("Unable to load emitter!\n");
	}


	// load updater
	ComputeProgram updater;
	if (!loadComputeProgram(psystemElement->FirstChildElement("updater"), updater))
	{
		printf("Unable to load updater!\n");
	}


	// load renderer
	RendererProgram renderer;
	if (!loadRenderer(psystemElement->FirstChildElement("renderer"), renderer))
	{
		printf("Unable to load renderer!\n");
	}

	// TODO: complete transform instead of only the position
	glm::mat4 model = glm::mat4();
	glm::vec3 pos = glm::vec3();
	TiXmlElement* position = psystemElement->FirstChildElement("position");
	position->QueryFloatAttribute("x", &pos.x);
	position->QueryFloatAttribute("y", &pos.y);
	position->QueryFloatAttribute("z", &pos.z);
	model = glm::translate(model, pos);

	// lifetime
	unsigned int lifetime;
	std::string unit;
	TiXmlElement* lifetimeElem = psystemElement->FirstChildElement("lifetime");
	lifetimeElem->QueryUnsignedAttribute("limit", &lifetime);
	lifetimeElem->QueryStringAttribute("unit", &unit);
	lifetime *= (unit == "millisec") ? 1 : 1000;

	return ParticleSystem(emitter, updater, renderer, model, lifetime);
}


///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
bool ParticleSystemLoader::loadBuffers(TiXmlElement * buffers)
{
	if (!buffers)
	{
		printf("No buffer resources found!\n");
		return false;
	}

	GLint bufMask = GL_MAP_WRITE_BIT | GL_MAP_INVALIDATE_BUFFER_BIT;


	// iterate through every buffer resource
	TiXmlElement* buffer = buffers->FirstChildElement();
	for (; buffer; buffer = buffer->NextSiblingElement())
	{
		bufferInfo bi;

		// parse buffer info and store <name, bufferInfo> pair
		glGenBuffers(1, &bi.id);
		buffer->QueryUnsignedAttribute("elements", &bi.elements);
		buffer->QueryStringAttribute("type", &bi.type);

		std::string bName;
		buffer->QueryStringAttribute("name", &bName);

		bufferHandles.emplace(bName, bi);

		// initialize buffer
		int bSize = bi.elements * ((bi.type == "vec4") ? 4 : 1);

		glBindBuffer(GL_SHADER_STORAGE_BUFFER, bufferHandles.at(bName).id);
		glBufferData(	GL_SHADER_STORAGE_BUFFER, bSize * sizeof(GLfloat),
						NULL, GL_DYNAMIC_DRAW);

		// fill buffer with default values
		GLfloat *values = (GLfloat*)glMapBufferRange(GL_SHADER_STORAGE_BUFFER, 0, bSize * sizeof(GLfloat), bufMask);
		for (int i = 0; i < bSize; values[i++] = 0);

		glUnmapBuffer(GL_SHADER_STORAGE_BUFFER);

		std::cout << "loaded buffer " << bName << " with number " << bufferHandles.at(bName).id
			<< ", " << bi.elements << " elements and size " << bSize << std::endl; // DUMP
	}

	return true;
}


///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
bool ParticleSystemLoader::loadAtomics(TiXmlElement * atomics)
{
	if (!atomics)
	{
		printf("No atomic resources found!\n");
		return false;
	}

	// iterate through every atomic resource
	TiXmlElement* atomic = atomics->FirstChildElement();
	for (; atomic; atomic = atomic->NextSiblingElement())
	{
		atomicInfo ai;

		// parse atomic info and store <name, atomicInfo> pair
		glGenBuffers(1, &ai.id);
		atomic->QueryUnsignedAttribute("value", &ai.initialValue);

		std::string atmName;
		atomic->QueryStringAttribute("name", &atmName);

		atomicHandles.emplace(atmName, ai);

		// initialize atomic buffer
		glBindBuffer(GL_ATOMIC_COUNTER_BUFFER, ai.id);
		glBufferData(GL_ATOMIC_COUNTER_BUFFER, sizeof(GLuint), NULL, GL_DYNAMIC_DRAW);
		glBufferSubData(GL_ATOMIC_COUNTER_BUFFER, 0, sizeof(GLuint), &ai.initialValue);

		std::cout << "loaded atomic " << atmName << " with number " <<
			ai.id << " and starting value " << ai.initialValue << std::endl;
	}

	return true;
}


///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
bool ParticleSystemLoader::loadUniforms(TiXmlElement * uniforms)
{
	if (!uniforms)
	{
		printf("No uniform resources found!\n");
		return false;
	}

	// iterate through every uniform resource
	TiXmlElement* uniform = uniforms->FirstChildElement();
	for (; uniform; uniform = uniform->NextSiblingElement())
	{
		uniformInfo ui;

		// parse uniform and store <name, atomicInfo> pair
		uniform->QueryFloatAttribute("value", &ui.value);
		uniform->QueryStringAttribute("type", &ui.type);
		std::string uName;
		uniform->QueryStringAttribute("name", &uName);

		uniformHandles.emplace(uName, ui);

		std::cout << "loaded uniform " << uName<< " of type " <<
			ui.type << " and value " << ui.value << std::endl;
	}

	return true;
}


///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
void ParticleSystemLoader::loadProgramResources(TiXmlElement* resources, atomicUmap &aum, bufferUmap &bum, uniformUmap &uum, std::vector<GLuint> &aToReset)
{
	// atomics
	std::string atmName;
	TiXmlElement* atomic = resources->FirstChildElement("atomics")->FirstChildElement();
	for (; atomic; atomic = atomic->NextSiblingElement())
	{
		atomic->QueryStringAttribute("name", &atmName);
		aum.emplace(atmName, atomicHandles.at(atmName));

		std::string resetValue;
		if (atomic->QueryStringAttribute("reset", &resetValue) == TIXML_SUCCESS)
		{
			if (resetValue == "true")
				aToReset.push_back(aum.at(atmName).id);
		}
	}

	// buffers
	std::string bName;
	TiXmlElement* buffer = resources->FirstChildElement("buffers")->FirstChildElement();
	for (; buffer; buffer = buffer->NextSiblingElement())
	{
		buffer->QueryStringAttribute("name", &bName);

		bum.emplace(bName, bufferHandles.at(bName));
	}

	// uniforms
	std::string uName;
	TiXmlElement* uniform = resources->FirstChildElement("uniforms")->FirstChildElement();
	for (; uniform; uniform = uniform->NextSiblingElement())
	{
		uniform->QueryStringAttribute("name", &uName);

		uum.emplace(uName, uniformHandles.at(uName));
	}
}


///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
bool ParticleSystemLoader::loadComputeProgram(TiXmlElement* glpElement, ComputeProgram &glp)
{
	// parse and store program resource handles for later binding
	TiXmlElement* resourcesElement = glpElement->FirstChildElement("resources");
	atomicUmap cpAtomicHandles;
	bufferUmap cpBufferHandles;
	uniformUmap cpUniforms;
	std::vector<GLuint> cpAtmHandlesToReset;

	loadProgramResources(resourcesElement, cpAtomicHandles, cpBufferHandles, cpUniforms, cpAtmHandlesToReset);


	GLuint cpHandle = glCreateProgram();
	GLuint cpShader = glCreateShader(GL_COMPUTE_SHADER);

	// parse file fragment paths that compose final shader
	std::vector<std::string> fPaths;
	std::string fragmentPath;

	TiXmlElement* fPathElement = glpElement->FirstChildElement("files")->FirstChildElement();
	for (; fPathElement; fPathElement = fPathElement->NextSiblingElement())
	{
		fPathElement->QueryStringAttribute("path", &fragmentPath);

		fPaths.push_back(fragmentPath);
	}

	// generate shader header from resource info
	std::string header = generateHeader(cpAtomicHandles, cpBufferHandles, cpUniforms);
	// fetch reserved functionality
	// TODO: add more
	std::string reservedFunctions = fileToString("reserved/noise2D.glsl");

	// compile, attach and check link status
	compileShaderFiles(cpShader, header, reservedFunctions, fPaths, true);
	glAttachShader(cpHandle, cpShader);
	glLinkProgram(cpHandle);

	GLint programSuccess = GL_FALSE;
	glGetProgramiv(cpHandle, GL_LINK_STATUS, &programSuccess);
	if (programSuccess == GL_FALSE)
	{
		printf("Error linking program %d!\n", cpHandle);
		printProgramLog(cpHandle);
		return false;
	}

	// create GLProgram, storing only the handles of buffers and atomics
	std::vector<GLuint> cpAtmHandles;
	for each (auto atm in cpAtomicHandles)
	{
		cpAtmHandles.push_back(atm.second.id);
	}

	std::vector<GLuint> cpBHandles;
	for each (auto b in cpBufferHandles)
	{
		cpBHandles.push_back(b.second.id);
	}

	glp = ComputeProgram(cpHandle, cpAtmHandles, cpAtmHandlesToReset, cpBHandles, cpUniforms);

	return true;
}


///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
bool ParticleSystemLoader::loadRenderer(TiXmlElement* glpElement, RendererProgram &rp)
{
	// parse and store program resource handles for later binding
	TiXmlElement* resourcesElement = glpElement->FirstChildElement("resources");
	atomicUmap rendAtomicHandles;
	bufferUmap rendBufferHandles;
	uniformUmap rendUniforms;
	std::vector<GLuint> rendAtmHandlesToReset;

	loadProgramResources(resourcesElement, rendAtomicHandles, rendBufferHandles, rendUniforms, rendAtmHandlesToReset);


	GLuint rpHandle = glCreateProgram();

	// vertex shader
	GLuint rpVertShader = glCreateShader(GL_VERTEX_SHADER);

	// parse file fragments
	std::vector<std::string> vertFrags;
	std::string fragmentPath;

	TiXmlElement* fPathElement = glpElement->FirstChildElement("vertfiles")->FirstChildElement();
	for (; fPathElement; fPathElement = fPathElement->NextSiblingElement())
	{
		fPathElement->QueryStringAttribute("path", &fragmentPath);

		vertFrags.push_back(fragmentPath);
	}

	// compile, attach
	compileShaderFiles(rpVertShader, "", "", vertFrags, true);
	glAttachShader(rpHandle, rpVertShader);


	// frag shader
	GLuint rpFragShader = glCreateShader(GL_FRAGMENT_SHADER);

	// parse file fragments
	std::vector<std::string> fragFrags;

	fPathElement = glpElement->FirstChildElement("fragfiles")->FirstChildElement();
	for (; fPathElement; fPathElement = fPathElement->NextSiblingElement())
	{
		fPathElement->QueryStringAttribute("path", &fragmentPath);

		fragFrags.push_back(fragmentPath);
	}

	// compile, attach and check link status
	compileShaderFiles(rpFragShader, "", "", fragFrags, true);
	glAttachShader(rpHandle, rpFragShader);

	glLinkProgram(rpHandle);

	GLint programSuccess = GL_FALSE;
	glGetProgramiv(rpHandle, GL_LINK_STATUS, &programSuccess);
	if (programSuccess == GL_FALSE)
	{
		printf("Error linking program %d!\n", rpHandle);
		printProgramLog(rpHandle);
		return false;
	}

	// get correct atomics
	std::vector<GLuint> rendAtmHandles;
	for each (auto atm in rendAtomicHandles)
	{
		rendAtmHandles.push_back(atm.second.id);
	}

	// generate vertex array object
	GLuint vao;
	glGenVertexArrays(1, &vao);
	glBindVertexArray(vao);

	// add buffers to vao
	for each (auto b in rendBufferHandles)
	{
		GLint location = glGetAttribLocation(rpHandle, b.first.c_str());
		glBindBuffer(GL_ARRAY_BUFFER, b.second.id);
		glEnableVertexAttribArray(location);
		GLuint elemType = (b.second.type == "float") ? 1 : 4;
		glVertexAttribPointer(location, elemType, GL_FLOAT, 0, 0, 0);
	}

	rp = RendererProgram(rpHandle, rendAtmHandles, vao, rendUniforms);

	return true;
}


///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
bool ParticleSystemLoader::compileShaderFiles(GLuint shaderID, std::string header, std::string reservedFunctions, std::vector<std::string> fPaths, bool dumpToFile)
{
	// parse file fragments into string
	std::string shaderString = header + reservedFunctions;
	for each (std::string fPath in fPaths)
	{
		shaderString = shaderString + fileToString(fPath);
	}

	if (dumpToFile)
	{
		std::string name = "dumps/" + std::to_string(shaderID) + "_shader.comp";
		std::ofstream out(name);
		out << shaderString;
		out.close();
	}

	const GLchar* shaderSource = shaderString.c_str();
	glShaderSource(shaderID, 1, (const GLchar**)&shaderSource, NULL);
	glCompileShader(shaderID);

	GLint cShaderCompiled = GL_FALSE;
	glGetShaderiv(shaderID, GL_COMPILE_STATUS, &cShaderCompiled);
	if (cShaderCompiled != GL_TRUE)
	{
		printf("Unable to compile compute shader %d!\n", shaderID);
		printShaderLog(shaderID);
		return false;
	}

	return true;
}


///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
std::string ParticleSystemLoader::fileToString(std::string filePath)
{
	std::string str;
	std::ifstream sourceFile(filePath.c_str());
	if (sourceFile)
	{
		str.assign((std::istreambuf_iterator< char >(sourceFile)),
			std::istreambuf_iterator< char >());
	}

	return str;
}


///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
void ParticleSystemLoader::printShaderLog(GLuint shader)
{
	// check if input is really a shader
	if (glIsShader(shader))
	{
		int infoLogLength = 0;
		int maxLength = 0;

		// get info string maxlength
		glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &maxLength);

		char* infoLog = new char[maxLength];

		// get info log
		glGetShaderInfoLog(shader, maxLength, &infoLogLength, infoLog);
		if (infoLogLength > 0)
		{
			printf("%s\n", infoLog);
		}

		// deallocate string
		delete[] infoLog;
	}
	else
	{
		printf("Name %d is not a shader\n", shader);
	}
}


///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
void ParticleSystemLoader::printProgramLog(GLuint program)
{
	// check if input is really a program
	if (glIsProgram(program))
	{
		int infoLogLength = 0;
		int maxLength = 0;

		// get info string max length
		glGetProgramiv(program, GL_INFO_LOG_LENGTH, &maxLength);

		char* infoLog = new char[maxLength];

		// get info log
		glGetProgramInfoLog(program, maxLength, &infoLogLength, infoLog);
		if (infoLogLength > 0)
		{
			printf("%s\n", infoLog);
		}

		// deallocate string
		delete[] infoLog;
	}
	else
	{
		printf("Name %d is not a program\n", program);
	}
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
std::string ParticleSystemLoader::generateHeader(atomicUmap glpAtomicHandles, bufferUmap cpBufferHandles, uniformUmap cpUniforms)
{
	std::string res =	"#version 430\n"
						"#extension GL_ARB_compute_shader : enable\n"
						"#extension GL_ARB_shader_storage_buffer_object : enable\n"
						"#extension GL_ARB_compute_variable_group_size : enable\n\n";

	int i = 0;
	// TODO: reserved atomics
	for each (auto atm in glpAtomicHandles)
	{
		res +=	"layout(binding = " + std::to_string(i++) +
				", offset = 0) uniform atomic_uint " + atm.first +";\n";
	}

	res += "\n";

	// TODO: reserved buffers
	for each(auto buf in cpBufferHandles)
	{
		std::string aux = buf.first;
		aux[0] = toupper(aux[0]);

		res +=	"layout(std430, binding = " + std::to_string(i++) + ") buffer " + aux + "\n{\n"
				"\t" + buf.second.type + " " + buf.first + "[];\n};\n\n";
	}

	res += "layout(local_size_variable) in;\n\n";

	for each (auto uni in cpUniforms)
	{
		res += "uniform " + uni.second.type + " " + uni.first + ";\n";
	}

	res += "\n";

	return res;
}