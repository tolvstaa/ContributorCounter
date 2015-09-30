#!/bin/bash

errprintf() { if ! [ -t 1 ]; then printf "$@" 1>&2; fi; }
errexit() { if [ "$?" -ne 0 ]; then errprintf "$@\n"; exit 1; fi }

scrape() {
	if [ ! -r "$1" ]; then
		errexit "Scrape called with bad parameter: \"$1\""
		exit 1
	fi
	
	# 0: authorpre
	# 1: author
	# 2: commit
	# 3: date
	# 4: print
	status=0

	while read line; do
		case "$status" in 
			0)
				if [[ $line =~ "committer_name" ]]; then
					((status++))
					continue
				fi
				;;

			1)
				#printf author
				author="$(echo $line | sed 's/^<[^>]*>//g' | sed 's/<.*$//g')"
				((status++))
				continue
				;;

			2)
				if [[ $line =~ "commit_id" ]]; then
					# printf commit id
					commit="$(echo $line | sed 's/^.*commit_id=\"//g' | sed 's/\" project_id.*$//g')"
					((status++))
					continue
				fi
				;;

			3)
				if [[ $line =~ "date" ]]; then
					# printf date
					date="$(echo $line | sed "s/^.*title='//g" | sed "s/'.$//g")"
					((status++))
					continue
				fi
				;;

			4)
				echo "$commit,$date,$author"
				status=0
				;;
		esac
	done < $1
}

#variables
cd "$( dirname "${BASH_SOURCE[0]}" )"
[ -d temp ] || { rm -f temp; mkdir temp; }
temphtml="./temp/contribs_html_tmp"
tempcsv="./temp/contribs_csv_tmp"
rm -f $temphtml $tempcsv
project=""
pages=1

# args
[ -n "$1" ] || { printf "Usage: $0 projectname > file\n"; exit 1; }
project="$1"
url="https://www.openhub.net/p/$project/commits"
errprintf "Using commits from project \"$project\" at $url.\n"

# get page count
errprintf "Initial download...\n" 
curl -s $url > $temphtml
errexit "Project unreachable.\n"

pages="$(grep "Showing page" $temphtml | sed 's/.*1 of //g' | cut -d"<" -f1 | sed 's/,//g')"
errprintf "$pages pages to scrape.\n"

# scrape pages
for i in $(seq 1 $pages); do
	errprintf "\rProcessing page $i of ${pages}..."
	curl -s $(echo "$url?page=$i") > $temphtml
	sed -i "1,/tbody/d" $temphtml
	scrape $temphtml >> $tempcsv
done

rm -f $temphtml
errprintf "\n$pages pages of commits scraped for project \"$project\" at ${url}.\n"


errprintf "Calculating stats...\n"
echo "--------$project--------"
firstyear="$(tail -n1 $tempcsv | cut -d"," -f2 | head -c4)"
lastyear="$(head -n1 $tempcsv | cut -d"," -f2 | head -c4)"
declare -a committers
yearly=""

# for each year in the range
for year in $(seq $firstyear $lastyear | tac); do
	current="$(grep -E "^[0-9]*,${year}.*$" $tempcsv | cut -d"," -f3 | sort | uniq | wc -l)"
	yearly="${yearly}$year: $current\n"
	committers=( "${committers[@]} $current" )
done

printf "$yearly" | tac

# compute and print average
total=0
for var in ${committers[@]}; do
	total=$(( $total + $var ))
done
printf "Average per year: $(awk "BEGIN {print $total/($lastyear-$firstyear+1)}")\n\n"

rm -f $tempcsv

errprintf "Calculations completed successfully.\n\n"
