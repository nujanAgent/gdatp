def can_build(env, platform):
    # GDatp's tool host lives in its Android editor only.
    return platform == "android" and env.editor_build


def configure(env):
    pass
