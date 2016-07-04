#pragma once
#include "RendererProgram.h"
#include "ComputeProgram.h"

class GP_ParticleSystem
{
	friend class ComputeProgram;

public:
	GP_ParticleSystem(ComputeProgram &e, ComputeProgram &u, RendererProgram &r, glm::mat4 &m, GLuint nwg, GLuint lif, bool lp)
		: emitter(e), updater(u), renderer(r), psModel(m), numWorkGroups(nwg), lifetime(lif), infinite(lif == 0), looping(lp) {};
	~GP_ParticleSystem();

	void execute(glm::mat4 model, glm::mat4 view, glm::mat4 projection);
	void printContents();
	bool isAlive();

private:
	ComputeProgram emitter;
	ComputeProgram updater;
	RendererProgram renderer;

	glm::mat4 psModel;

	GLuint numWorkGroups;

	// lifetime
	bool infinite = true;
	bool looping = false;
	GLuint lifetime;
	GLuint lifeStart;
	bool alive = true;
	bool firstExec = true;
};