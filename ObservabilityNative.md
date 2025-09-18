# How observability native works
- GraalPy builds all the c dependencies of python packages using CC
- Therefore we can't use jar generated in one system in another.
- At the same time the actual python interpreter of graalpy is suppose to be cross platform
- Also we **can't** dynamically load the graalpy interpreter

- Therefore we have a separate observability-native subproject that in CI we build separate jars for mac and linux.
    - These are **thin jars** We only need the python vnenv for each system since we can't anyway load the graalpy using these jars
- Then we pack these jars in native which will have graalpy as an dependency. So it should have the interpreter.
- We then based on the system dynamically load the corresponding jar at runtime. So in order to execute the python code we get the native dependencies from the thin jar and python interpreter form native directly.
