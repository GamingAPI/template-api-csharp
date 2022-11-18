#!/bin/bash
set -e

# Cleanup potential old files
[ -d "./tooling" ] && rm -rf ./tooling

# Initial setup of variables
libary_name="<<[ .cus.LIBRARY_NAME ]>>"
repository_url="<<[ .cus.REPOSITORY_URL ]>>"
library_last_version="0.0.0"
template_last_version="0.0.0"
template_current_version="0.0.0"
document_last_version="0.0.0"
document_current_version="0.0.0"
major_template_last_version=0
minor_template_last_version=0
patch_template_last_version=0
major_template_current_version=0
minor_template_current_version=0
patch_template_current_version=0
major_version_change="false"
minor_version_change="false"
patch_version_change="false"
commit_message=""
document_last_version=$(cat ./configs.json | jq -r '.document_last_version')
template_last_version=$(cat ./configs.json | jq -r '.template_last_version')
template_to_use="jonaslagoni/dotnet-nats-template"
template_current_version=$(curl -sL https://raw.githubusercontent.com/${template_to_use}/master/package.json | jq -r '.version' | sed 's/v//')
url_to_asyncapi_document="https://raw.githubusercontent.com/GamingAPI/definitions/main/bundled/<<[ .cus.ASYNCAPI_FILE ]>>"
document_current_version=$(curl -sL ${url_to_asyncapi_document} | jq -r '.info.version' | sed 's/v//')

if [ -f "./${libary_name}/${libary_name}.csproj" ]; then
  if ! command -v xml-to-json &> /dev/null
  then
    git clone https://github.com/tyleradams/json-toolkit.git tooling
    cd ./tooling && make json-diff json-empty-array python-dependencies && sudo make install
    cd ..
  fi
  library_last_version=$(cat ./${libary_name}/${libary_name}.csproj | xml-to-json | jq -r '.Project.PropertyGroup.Version')
else
  library_last_version="0.0.0"
fi

# Split the last used template version by '.' to split it up into 'major.minor.fix'
semver_template_last_version=( ${template_last_version//./ } )
major_template_last_version=${semver_template_last_version[0]}
minor_template_last_version=${semver_template_last_version[1]}
patch_template_last_version=${semver_template_last_version[2]}
# Split the current template version by '.' to split it up into 'major.minor.fix'
semver_template_current_version=( ${template_current_version//./ } )
major_template_current_version=${semver_template_current_version[0]}
minor_template_current_version=${semver_template_current_version[1]}
patch_template_current_version=${semver_template_current_version[2]}
if [[ $major_template_current_version > $major_template_last_version ]]; then major_template_change="true"; else major_template_change="false"; fi
if [[ $minor_template_current_version > $minor_template_last_version ]]; then minor_template_change="true"; else minor_template_change="false"; fi
if [[ $patch_template_current_version > $patch_template_last_version ]]; then patch_template_change="true"; else patch_template_change="false"; fi

# Split the last used AsyncAPI document version by '.' to split it up into 'major.minor.fix'
semver_document_last_version=( ${document_last_version//./ } )
major_document_last_version=${semver_document_last_version[0]}
minor_document_last_version=${semver_document_last_version[1]}
patch_document_last_version=${semver_document_last_version[2]}
# Split the current AsyncAPI document version by '.' to split it up into 'major.minor.fix'
semver_document_current_version=( ${document_current_version//./ } )
major_document_current_version=${semver_document_current_version[0]}
minor_document_current_version=${semver_document_current_version[1]}
patch_document_current_version=${semver_document_current_version[2]}
if [[ $major_document_current_version > $major_document_last_version ]]; then major_document_change="true"; else major_document_change="false"; fi
if [[ $minor_document_current_version > $minor_document_last_version ]]; then minor_document_change="true"; else minor_document_change="false"; fi
if [[ $patch_document_current_version > $patch_document_last_version ]]; then patch_document_change="true"; else patch_document_change="false"; fi

# Set the commit messages that details what changed
if [ $major_template_change == "true" ]; then
  commit_message="Template have changed to a new major version."
elif [ $minor_template_change == "true" ]; then
  commit_message="Template have changed to a new minor version."
elif [ $patch_template_change == "true" ]; then
  commit_message="Template have changed to a new patch version."
fi
if [ $major_document_change == "true" ]; then
  commit_message="${commit_message}AsyncAPI document have changed to a new major version."
elif [ $minor_document_change == "true" ]; then
  commit_message="${commit_message}AsyncAPI document have changed to a new minor version."
elif [ $patch_document_change == "true" ]; then
  commit_message="${commit_message}AsyncAPI document have changed to a new patch version."
fi

# Always use the most aggressive version change, and only do one type of version change
if [ $major_template_change == "true" ] || [ $major_document_change == "true" ]; then
  major_version_change="true"
elif [ $minor_template_change == "true" ] || [ $minor_document_change == "true" ]; then
  minor_version_change="true"
elif [ $patch_template_change == "true" ] || [ $patch_document_change == "true" ]; then
  patch_version_change="true"
fi

if [ $major_version_change == "true" ] || [ $minor_version_change == "true" ] || [ $patch_version_change == "true" ]; then
  # Remove previous generated files to ensure clean slate
  find . -not \( -name configs.json -or -name .gitignore -or -name LICENSE -or -name generate.sh -or -iwholename *.github* -or -iwholename *.git* -or -name . \) -exec rm -rf {} +

  if ! command -v ag &> /dev/null
  then
    npm install -g @asyncapi/generator
  fi
  # Generating new code from the AsyncAPI document
  ag --force-write --output ./ ${url_to_asyncapi_document} https://github.com/${template_to_use} -p version="${library_last_version}" -p targetFramework="netstandard2.0;netstandard2.1;net461" -p repositoryUrl="${repository_url}" -p projectName="${libary_name}" -p packageVersion="${library_last_version}" -p assemblyVersion="${library_last_version}.0" -p serializationLibrary="newtonsoft" -p fileVersion="${library_last_version}.0"

  # Write new config file to ensure we keep the new state for next time
  contents="$(jq ".template_last_version = \"$template_current_version\" | .document_last_version = \"$document_current_version\"" configs.json)" && echo "${contents}" > configs.json
fi
mkdir -p ./.github/variables

echo "
major_version_change=$major_version_change
minor_version_change=$minor_version_change
patch_version_change=$patch_version_change
commit_message=$commit_message
" > ./.github/variables/generator.env

# Cleanup
rm -rf ./tooling