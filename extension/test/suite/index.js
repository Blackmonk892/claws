const path = require('path');
const Mocha = require('mocha');
const glob = require('glob');

function run() {
  const mocha = new Mocha({
    ui: 'tdd',
    color: true,
  });

  const testsRoot = path.resolve(__dirname, '..');

  return new Promise((resolve, reject) => {
    const globPattern = path.join(testsRoot, 'suite', '**', '*.test.js');
    glob.glob(globPattern, (err, files) => {
      if (err) {
        return reject(err);
      }

      files.forEach((file) => mocha.addFile(path.resolve(file)));

      try {
        mocha.run((failures) => {
          if (failures > 0) {
            reject(new Error(`${failures} tests failed.`));
          } else {
            resolve();
          }
        });
      } catch (err) {
        console.error(err);
        reject(err);
      }
    });
  });
}

module.exports = { run };
