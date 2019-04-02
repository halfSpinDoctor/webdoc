function webdoc(varargin)
    %  WEBDOC Reference page in Help browser.
    %  
    %     WEBDOC opens the Help browser, if it is not already running, and 
    %     otherwise brings the Help browser to the top.
    %   
    %     WEBDOC FUNCTIONNAME displays the reference page for FUNCTIONNAME in
    %     the Help browser. FUNCTIONNAME can be a function or block in an
    %     installed MathWorks product.
    %   
    %     WEBDOC METHODNAME displays the reference page for the method
    %     METHODNAME. You may need to run DOC CLASSNAME and use links on the
    %     CLASSNAME reference page to view the METHODNAME reference page.
    %   
    %     WEBDOC CLASSNAME displays the reference page for the class CLASSNAME.
    %     You may need to qualify CLASSNAME by including its package: DOC
    %     PACKAGENAME.CLASSNAME.
    %   
    %     WEBDOC CLASSNAME.METHODNAME displays the reference page for the method
    %     METHODNAME in the class CLASSNAME. You may need to qualify
    %     CLASSNAME by including its package: DOC PACKAGENAME.CLASSNAME.
    %   
    %     WEBDOC FOLDERNAME/FUNCTIONNAME displays the reference page for the
    %     FUNCTIONNAME that exists in FOLDERNAME. Use this syntax to display the
    %     reference page for an overloaded function.
    %   
    %     WEBDOC USERCREATEDCLASSNAME displays the help comments from the
    %     user-created class definition file, UserCreatedClassName.m, in an
    %     HTML format in the Help browser. UserCreatedClassName.m must have a
    %     help comment following the classdef UserCreatedClassName statement
    %     or following the constructor method for UserCreatedClassName. To
    %     directly view the help for any method, property, or event of
    %     UserCreatedClassName, use dot notation, as in DOC
    %     USERCREATEDCLASSNAME.METHODNAME. 
    %
    %     Examples:
    %        webdoc abs
    %        webdoc fixedpoint/abs  % ABS function in the Fixed-Point Designer Product
    %        webdoc handle.findobj  % FINDOBJ method in the HANDLE class
    %        webdoc handle          % HANDLE class
    %        webdoc containers.Map  % Map class in the containers method
    %        webdoc sads            % User-created class, sads
    %        webdoc sads.steer      % steer method in the user-created class, sads

    %   'doc' command Copyright 1984-2013 The MathWorks, Inc.
    %
    %   'webdoc' command created by Samuel A. Hurley, 2019
    %   webdoc is a modified version of 'doc', and as such is not
    %   distributed any under particular license.
    %
    %   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
    %   AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
    %   IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
    %   ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
    %   LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
    %   DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
    %   SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    %   CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
    %   OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
    %   USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
    
    % ====================== webdoc Configuration Section ======================
    
    global browserCommand;
    global docPageURL docSearchURL;
    
    % Unix command for launching the web browser (no trailing space)
    browserCommand = 'firefox -new-tab';
    
    % MATHWORKS Help URLS (may change)
    docPageURL   = 'https://www.mathworks.com/help/';
    docSearchURL = 'https://www.mathworks.com/help/search.html?qdoc=';
    % ======================  end Configuration Section  =======================
    
    % Make sure that we can support the doc command on this platform.
    if ~usejava('mwt')
        error(message('MATLAB:doc:UnsupportedPlatform', upper(mfilename)));
    end

    % Examine the inputs to see what options are selected.
    [showClassicDoc, topic, search, isVariable] = examineInputs(varargin{:});
    if isVariable
        varName = inputname(isVariable);
    elseif ~isempty(topic) && nargin == 1
        wsVariables = evalin('caller', 'whos');
        [topic, isVariable, varName] = helpUtils.getClassNameFromWS(topic, wsVariables, true);
    end
    if search
        docsearch(topic);
        return;
    end

    % Check this before checking docroot, the -classic option is used to show doc not under docroot.
    if showClassicDoc
        com.mathworks.mlservices.MLHelpServices.invokeClassicHelpBrowser();
        return;
    end

    % Make sure docroot is valid.
    if ~helpUtils.isDocInstalled
        % If m-file help is available for this topic, call helpwin.
        if ~isempty(topic)
            if showHelpwin(topic)
                return;
            end
        end

        % Otherwise show the appropriate error page.
        htmlFile = fullfile(matlabroot,'toolbox','local','helperr.html');

        if exist(htmlFile, 'file') ~= 2
            error(message('MATLAB:doc:HelpErrorPageNotFound', htmlFile));
        end
        displayFile(htmlFile);
        return;
    end

    % Case no topic specified.
    if isempty(topic)
        % Just open the help browser and display the default startup page.
        com.mathworks.mlservices.MLHelpServices.invoke();
        return;
    end
    
    if strncmpi(topic, 'mupad/', 6)
        if ~mupaddoc(topic)
            showNoReferencePageFound;
        end
        return;
    end
    
    [operator,topic] = matlab.internal.language.introspective.isOperator(topic);
    if ~operator
        if topic(end) == '/'
            topic = topic(1:end-1);
        end

        if showProductPage(topic)
            return;
        end
        
        [possibleTopics, isPrimitive] = helpUtils.resolveDocTopic(topic, isVariable);
        
        if isPrimitive
            disp(helpUtils.getInstanceIsa(varName, topic));
            return;
        end
    else
        [~,possibleTopics.topic] = fileparts(topic);
        possibleTopics.isElement = false;
    end
    
    if ~displayDocPage(possibleTopics) && ~showHelpwin(topic)
        docsearch(topic);
    end
end

function [showClassicDoc, topic, search, varIndex] = examineInputs(varargin)
    showClassicDoc = 0;
    topic = [];
    search = 0;
    varIndex = 0;

    for i = 1:numel(varargin)
        argName = varargin{i};
        if isstring(argName)
            if ~isscalar(argName)
                MException(message('MATLAB:doc:MustBeSingleString')).throwAsCaller;
            end
            argName = char(strip(argName));
        elseif ischar(argName)
            argName = strtrim(argName);
        else
            argName = class(argName);
            varIndex = i;
        end

        if strcmp(argName, '-classic')
            showClassicDoc = 1;
        else
            % assume this is the location.
            if ~isempty(topic)
                topic = sprintf('%s %s', topic, argName);
                search = 1;
            else
                topic = argName;
            end
        end
    end
end
    
function success = showProductPage(topic)
    global browserCommand docPageURL;
    success = false;
    
    url = [docPageURL topic '/index.html'];
    
    % Check if URL exists
    [status cmdout] = unix(['wget -S --spider --server-response ' lower(url) ' 2>&1 | grep "HTTP/"']);  

    if strcmp(strtrim(cmdout), 'HTTP/1.1 200 OK')
        unix([browserCommand ' ' lower(url) ' &']);
        success = true;
        return;
    end
    
end

function success = displayDocPage(possibleTopics)
    global browserCommand docPageURL;
    % Iterate over possible topics, and see if page exists on Mathworks site
    success = false;
    for topic = possibleTopics
        thisTopic = strsplit(topic.topic, '/');
        
        % Determine which product/toolbox
        if strcmp(thisTopic{1}, '(matlab)')
          % Search URL is MATLAB product reference
          toolbox = 'matlab';
          thisTopic(1) = []; % Remove the first element of the cell array
          
        else
          % Search URL is toolbox reference
          toolbox = thisTopic{1};
          thisTopic(1) = [];
        end

        for ii = 1:length(thisTopic)   
            url = [docPageURL toolbox '/ref/' strjoin(thisTopic(ii:end), '.') '.html']

            % Check if URL exists
            [status cmdout] = unix(['wget -S --spider --server-response ' lower(url) ' 2>&1 | grep "HTTP/"']);  

            if strcmp(strtrim(cmdout), 'HTTP/1.1 200 OK')
                unix([browserCommand ' ' lower(url) ' &']);
                success = true;
                return;
            end
        end
        
        % As a last resort, check if this topic is a class
        if length(thisTopic) > 0 && exist(thisTopic{end}, 'class')
          
            % Build up URL for a matlab class
            url = [docPageURL toolbox '/ref/' thisTopic{end}, '-class' '.html'];
            
            % Check if URL exists
            [status cmdout] = unix(['wget -S --spider --server-response ' url ' 2>&1 | grep "HTTP/"']);  

            if strcmp(strtrim(cmdout), 'HTTP/1.1 200 OK')
                unix([browserCommand ' ' lower(url) ' &']);
                success = true;
                return;
            end
        end
          
    end

end

function success = docsearch(topic)
    global browserCommand docSearchURL;
    % Call search URL for this string
    url = [docSearchURL topic];
    unix([browserCommand ' ' lower(url) ' &']);
    success = 1;
    
end

   
function foundTopic = showHelpwin(topic)
    global browserCommand;
    % Call help2html to generate a temporary html page to display in Firefox
    % Make the temp folder
    
    % Check if the non-builtin m-file exists
    if exist(topic, 'file')
      
        % Setup output directory and filename for HTML file
        % Use genvarname to avoid any illegal characters in the file path
        username = char(java.lang.System.getProperty('user.name'));
        dirname  = fullfile(tempdir,  genvarname(['matlab_' username]));
        fname    = fullfile(dirname, [genvarname(topic) '.html']);

        % Create directory, if it does not exist, and write out the file
        unix(['mkdir -p ' dirname]);
        fid = fopen(fname, 'w');
        fprintf(fid, '%s\n', help2html(topic));
        fclose(fid);

        % Finally, open the file in Firefox
        unix([browserCommand ' file://' fname ' &']);
        foundTopic = true;
    else
        foundTopic = false;
    end
    
%     % turn off the warning message about helpwin being removed in a future
%     % release
%     s = warning('off', 'MATLAB:helpwin:FunctionToBeRemoved');
%     
%      if helpUtils.isLiveFunctionAndHasDocumentation(topic)
%         internal.help.livecodedoc.mlxdoc(topic);
%         foundTopic = true;
%     else
%         foundTopic = helpwin(topic, '', '', '-doc');
%     end
% 
%     % turn the warning message back on if it was on to begin with
%     warning(s.state, 'MATLAB:helpwin:FunctionToBeRemoved');
end

function showNoReferencePageFound(topic)
    noFuncPage = helpUtils.underDocroot('nofunc.html');
    if ~isempty(noFuncPage)
        displayFile(noFuncPage);
    else
        error(message('MATLAB:doc:InvalidTopic', topic));
    end
end

function displayFile(htmlFile)
    % Display the file inside the help browser.
    web(htmlFile, '-helpbrowser');
end
