import numpy as np 
import os
import os.path as op
import shutil

from multiprocdmlab import default_entity_root, entity_dir
from deepmind_lab_gym import DeepmindLab, ActionMapperDiscrete
from zipfile import ZipFile
from multiprocessing import Pool
import fcntl

def random_variation_layer((r, c)):
    rint = np.random.randint(0 + ord('A'), 26 + ord('A'), size=(r, c), dtype='u1')
    return "\n".join(rint.view(dtype='|S%d' % c).reshape(r))

def mapfile_basename(mode, shape, idx):
    mapname = "%s-%02dx%02d-var-%04d" % (mode, shape[0], shape[1], idx)
    return mapname

def generate_map(idx
                 , num_maps = 1000
                 , mode='training'
                 , shape=(9, 9)):
    entitydir = entity_dir(default_entity_root(),
                           rows=shape[0], cols=shape[1], mode=mode)
    mapname = mapfile_basename(mode, shape, idx)
    entityFile = op.join(entitydir, "%04d.entityLayer" % idx)
    with open(entityFile) as f: entityLayer = f.read()
    variationsLayer = random_variation_layer(shape)
    variationsFile = op.splitext(entityFile)[0] + ".variationsLayer"
    with open(variationsFile, "w") as f: f.write(variationsLayer)

    config = dict(width=84, height=84, fps=30
                  , mapnames = mapname
                  , mapstrings = entityLayer
                  , variationsLayers = variationsLayer
                  , make_map = "True")
    print("Calling DeepmindLab")
    dl = DeepmindLab("random_mazes", config, ActionMapperDiscrete
                , additional_observation_types=[
                    "GOAL.LOC", "POSE", "GOAL.FOUND"])
    dl.step(0)

def level_data_dir():
    return "/tmp/dmlab_level_data_0/baselab/"
    

def mv_map_files(assets_map_location, pk3dir, mapname):
    mapfile, pk3file = [op.join(level_data_dir(), mapname + ext)
                        for ext in ".map .pk3".split()]
    try:
        print("Adding %s to %s" % (mapfile, assets_map_location))
        shutil.move(mapfile, assets_map_location)
    except shutil.Error, e:
        print(e)
    print("Adding %s to %s" % (pk3file, pk3dir))
    shutil.move(pk3file, pk3dir)
    for df in [op.join(level_data_dir(), mapname + "." + ext)
               for ext in "srf aas bsp".split()]:
        os.remove(df)
    for df in [op.join(level_data_dir(), "maps", mapname + "." + ext)
               for ext in "aas bsp".split()]:
        os.remove(df)

def exists_pk3_file(assets_pk3_path, fname):
    if not op.exists(assets_pk3_path):
        return False

    with open(assets_pk3_path, 'r') as f, \
         ZipFile(f, 'r') as zip, \
         FileLock(f, fcntl.LOCK_SH):
        return arcname_from_basename(fname) in zip.namelist()

def arcname_from_basename(basename):
    return op.join("maps", basename)

class FileLock(object):
    def __init__(self, fd, operation):
        self.fd = fd
        self.operation = operation

    def __enter__(self):
        fcntl.lockf(self.fd.fileno(), self.operation)

    def __exit__(self, *args):
        fcntl.lockf(self.fd.fileno(), fcntl.LOCK_UN)

def pack_pk3_files(assets_pk3_path, mapname):
    mapsdir = op.join(level_data_dir(), "maps/")
    files = [op.join(mapsdir, mapname + "." + ext)
             for ext in "bsp aas".split()]
    with open(assets_pk3_path, 'a') as f, \
         ZipFile(f, 'a') as zip, \
         FileLock(f, fcntl.LOCK_EX):
        for f in files:
            print("Adding %s to archive" % f)
            zip.write(f, arcname=arcname_from_basename(op.basename(f)))
            os.remove(f)

def make_map_and_copy(args):
    pk3dir, mapsdir, mapname, mode, idx = args
    if (op.exists(op.join(mapsdir, mapname + ".pk3"))
        and op.exists(op.join(mapsdir, mapname + ".map"))):
        print("File %s.map exists" % mapname)
        return mapname
    generate_map(idx, num_maps=False, mode=mode)
    mv_map_files(mapsdir, pk3dir, mapname)
    return mapname
    
def make_random_maps(thisdir = op.dirname(__file__) or '.'
                     , train_num_maps = 1000
                     , test_num_maps = 200
                     , shape = (9, 9)):
    mapsdir = op.join(thisdir, "../assets/maps/")
    pk3dir = op.join(thisdir, "../assets/pk3s/")
    pool = Pool(processes=4)
    mapnames = pool.map(make_map_and_copy
             , [(pk3dir, mapsdir
                  , mapfile_basename('training', shape, idx)
                  , 'training', idx)
                 for idx in range(1, train_num_maps + 1)]
             + [
                 (pk3dir, mapsdir
                  , mapfile_basename('testing', shape, idx)
                  , 'testing', idx)
                 for idx in range(1, train_num_maps + 1)])
    pk3path = op.join(pk3dir, 'var_maps.pk3')
    with ZipFile(pk3path, 'w') as zip:
        for pf in [op.join(pk3dir, f + ".pk3") for f in mapnames]:
            with ZipFile(pf, 'r') as pfzip:
                for pffile in pfzip.namelist():
                    zip.writestr(pffile, pfzip.read())

if __name__ == '__main__':
    make_random_maps()
