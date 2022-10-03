#!/bin/bash

# -- CONFIG ZONE START --
BIN="/usr/local/bin/gaiad" # set your chain binary
UPGRADE_PATH="/root/.gaia/upgrades"
SERVICE="gaiad.service"
CHAT_ID="11223344" # telegram chat id
BOT_KEY="1122334455:Aabb..." # telegram bot token
PREP_OFFSET=50 # number of blocks before upgrade height, to start download upgrade file and start whaiting loop
# -- CONFIG ZONE END --

echo "-------- $(date +"%d-%m-%Y %H:%M") start upgrade check --------"
voting_upgrade_proposal=$(${BIN} query gov proposals --status VotingPeriod --output json 2>/dev/null|jq -r '[.proposals[]|select(.content."@type"=="/cosmos.upgrade.v1beta1.SoftwareUpgradeProposal")]|max_by(.proposal_id|tonumber)')
passed_upgrade_proposal=$(${BIN} query gov proposals --status Passed --output json 2>/dev/null|jq -r '[.proposals[]|select(.content."@type"=="/cosmos.upgrade.v1beta1.SoftwareUpgradeProposal")]|max_by(.proposal_id|tonumber)')
upgrade_height=$(echo ${passed_upgrade_proposal}|jq -r '.content.plan.height')
current_height=$(${BIN} status|jq -r '.SyncInfo.latest_block_height')
if [[ -n ${voting_upgrade_proposal} ]]; then
        voting_upgrade_proposal_info=$(echo ${voting_upgrade_proposal}|jq -r '"Found new voting period proposal for chain upgrade to version: " + .content.plan.name + " at height: " + .content.plan.height + ", whaiting voting result"')
        echo "${voting_upgrade_proposal_info}"
#        curl -s -X POST -H 'Content-Type: application/json' -d '{"chat_id":"'"${CHAT_ID}"'", "text": "'"${voting_upgrade_proposal_info}"'", "parse_mode": "html"}' https://api.telegram.org/bot$BOT_KEY/sendMessage > /dev/null 2>&1
fi
if [[ -n ${upgrade_height} ]] && [[ ${current_height} -gt ${upgrade_height}-${PREP_OFFSET} ]] && [[ ${current_height} -lt ${upgrade_height} ]]; then
        upgrade_binary=$(echo ${passed_upgrade_proposal}|jq -r '.content.plan.info'|jq -r ".binaries.\"linux/"$(dpkg-architecture -q DEB_BUILD_ARCH)\")
        upgrade_name=$(echo ${passed_upgrade_proposal}|jq -r '.content.plan.name')
        if [[ -z ${upgrade_binary} ]]; then
                echo "No binary for current system arch in upgrade plan, need manual upgrade!"
                curl -s -X POST -H 'Content-Type: application/json' -d '{"chat_id":"'"${CHAT_ID}"'", "text": "No binary for current system architecture in upgrade proposal plan to version '"${upgrade_name}"', need manual upgrade! Upgrade will be at height '"${upgrade_height}"', current height '"${current_height}"'", "parse_mode": "html"}' https://api.telegram.org/bot$BOT_KEY/sendMessage > /dev/null 2>&1
                exit 1
        else
                curl -s -X POST -H 'Content-Type: application/json' -d '{"chat_id":"'"${CHAT_ID}"'", "text": "New upgrade '"${upgrade_name}"' will be applied at '"${upgrade_height}"', current height '"${current_height}"' ", "parse_mode": "html"}' https://api.telegram.org/bot$BOT_KEY/sendMessage > /dev/null 2>&1
                echo "Start upgrade preparations"
        fi
        echo "Download link: ${upgrade_binary}"
        mkdir -p ${UPGRADE_PATH}/${upgrade_name} && echo "Make new folder for upgrade: ${UPGRADE_PATH}/${upgrade_name}" || echo "ERROR creating dir ${UPGRADE_PATH}/${upgrade_name}"
        wget -q ${upgrade_binary} -O ${UPGRADE_PATH}/${upgrade_name}/upgrade.tar.gz && echo "Downloaded upgrade file to ${UPGRADE_PATH}/${upgrade_name}/upgrade.tar.gz" || echo "ERROR downloading upgrade file"
        sum=$(echo ${upgrade_binary}|sed -En 's/^.+sha256:(.+)/\1/p')
        if [[ -n ${sum} ]]; then echo "sha256sum of downloaded upgrade file must be ${sum}"; fi
        if [[ -n ${sum} ]] && [[ $(sha256sum ${UPGRADE_PATH}/${upgrade_name}/upgrade.tar.gz) = "${sum}  ${UPGRADE_PATH}/${upgrade_name}/upgrade.tar.gz" ]]; then
                echo "sha256sum of downloaded file is OK"
                chmod +x ${UPGRADE_PATH}/${upgrade_name}/$(tar -xvf ${UPGRADE_PATH}/${upgrade_name}/upgrade.tar.gz -C ${UPGRADE_PATH}/${upgrade_name}/) && echo "Unpack and make executable" || echo "ERROR unpacking downloaded file ${UPGRADE_PATH}/${upgrade_name}/upgrade.tar.gz"
                rm ${UPGRADE_PATH}/${upgrade_name}/upgrade.tar.gz
        elif [[ -n ${sum} ]] && [[ $(sha256sum ${UPGRADE_PATH}/${upgrade_name}/upgrade.tar.gz) != "${sum}  ${UPGRADE_PATH}/${upgrade_name}/upgrade.tar.gz" ]]; then
                echo "ERROR: sha256sum of downloaded file is NOT OK"
                exit 1
        elif [[ -z ${sum} ]]; then
                chmod +x ${UPGRADE_PATH}/${upgrade_name}/$(tar -xvf ${UPGRADE_PATH}/${upgrade_name}/upgrade.tar.gz -C ${UPGRADE_PATH}/${upgrade_name}/) && echo "Unpack and make executable" || echo "ERROR unpacking downloaded file ${UPGRADE_PATH}/${upgrade_name}/upgrade.tar.gz"
                rm ${UPGRADE_PATH}/${upgrade_name}/upgrade.tar.gz
                echo "Upgrade file downloaded and unpacked"
        fi

        for ((;;)); do
                current_height=$(${BIN} status|jq -r '.SyncInfo.latest_block_height')
                echo "Current height: ${current_height}, will upgrade to ${upgrade_name} at height: ${upgrade_height}"
                if [[ ${current_height} -eq ${upgrade_height} ]]; then
                        echo "Upgrade height has come, upgrading..."
                        rm -rf ${UPGRADE_PATH}/current && echo "Old symbolic link to binary removed"
                        ln -s ${UPGRADE_PATH}/${upgrade_name} ${UPGRADE_PATH}/current && echo "New symbolic link to binary version ${upgrade_name} was set"
                        sudo systemctl restart ${SERVICE} && echo "Service ${SERVICE} restarted" || echo "ERROR: service ${SERVICE} NOT restarted!"
                        sleep 30
                        current_height=$(${BIN} status|jq -r '.SyncInfo.latest_block_height')
                        if [[ ${current_height} -gt ${upgrade_height} ]]; then
                                echo "Upgrade succsessfully complete!"
                                curl -s -X POST -H 'Content-Type: application/json' \
                                -d '{"chat_id":"'"${CHAT_ID}"'", "text": "Upgrade to '"${upgrade_name}"' successfully complete at height '"${upgrade_height}"', current height '"${current_height}"'", "parse_mode": "html"}' https://api.telegram.org/bot$BOT_KEY/sendMessage > /dev/null 2>&1
                        else
                                echo "Node is not cathing up, need to investigate!"
                                curl -s -X POST -H 'Content-Type: application/json' \
                                -d '{"chat_id":"'"${CHAT_ID}"'", "text": "After upgrade node is not cathing up, current height '"${current_height}"'", "parse_mode": "html"}' https://api.telegram.org/bot$BOT_KEY/sendMessage > /dev/null 2>&1
                        fi
                        break
                fi
                sleep 5
        done
elif [[ -n ${upgrade_height} ]] && [[ ${current_height} -lt ${upgrade_height} ]] && [[ ${current_height} -le ${upgrade_height}-${PREP_OFFSET} ]]; then
        upgrade_name=$(echo ${passed_upgrade_proposal}|jq -r '.content.plan.name')
        echo "Current height: ${current_height}, will upgrade to ${upgrade_name} at height: ${upgrade_height}"
else
        echo "No active upgrade proposals"
fi
echo "-------- $(date +"%d-%m-%Y %H:%M") upgrade check done ---------"
