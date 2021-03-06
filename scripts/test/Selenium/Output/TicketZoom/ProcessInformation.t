# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;
use utf8;

use vars (qw($Self));

# get selenium object
my $Selenium = $Kernel::OM->Get('Kernel::System::UnitTest::Selenium');

$Selenium->RunTest(
    sub {

        # get needed objects
        $Kernel::OM->ObjectParamAdd(
            'Kernel::System::UnitTest::Helper' => {
                RestoreSystemConfiguration => 1,
            },
        );
        my $Helper          = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
        my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');

        # disable 'Customer Information' and 'Linked Objects' widgets in AgentTicketZoom screen
        for my $WidgetDisable (qw(0200-CustomerInformation 0300-LinkTable)) {
            $SysConfigObject->ConfigItemUpdate(
                Valid => 0,
                Key   => "Ticket::Frontend::AgentTicketZoom###Widgets###$WidgetDisable",
                Value => '',
            );
        }

        # do not check RichText, service and type
        $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'Frontend::RichText',
            Value => 0
        );
        $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'Ticket::Service',
            Value => 0
        );
        $SysConfigObject->ConfigItemUpdate(
            Valid => 1,
            Key   => 'Ticket::Type',
            Value => 0
        );

        # create test user and login
        my $TestUserLogin = $Helper->TestUserCreate(
            Groups => [ 'admin', 'users' ],
        ) || die "Did not get test user";

        $Selenium->Login(
            Type     => 'Agent',
            User     => $TestUserLogin,
            Password => $TestUserLogin,
        );

        # get test user ID
        my $TestUserID = $Kernel::OM->Get('Kernel::System::User')->UserLookup(
            UserLogin => $TestUserLogin,
        );

        # get config object
        my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

        # get script alias
        my $ScriptAlias = $ConfigObject->Get('ScriptAlias');

        # navigate to AdminProcessManagement screen
        $Selenium->VerifiedGet("${ScriptAlias}index.pl?Action=AdminProcessManagement");

        # import test selenium process scenario
        my $Location = $ConfigObject->Get('Home')
            . "/scripts/test/sample/ProcessManagement/TestProcess.yml";
        $Selenium->find_element( "#FileUpload",                      'css' )->send_keys($Location);
        $Selenium->find_element( "#OverwriteExistingEntitiesImport", 'css' )->click();
        $Selenium->find_element("//button[\@value='Upload process configuration'][\@type='submit']")->VerifiedClick();

        # wait until process is created
        $Selenium->WaitFor( JavaScript => 'return typeof($) === "function" && $(".Notice").length' );

        $Selenium->find_element("//a[contains(\@href, \'Subaction=ProcessSync' )]")->VerifiedClick();

        # let mod_perl / Apache2::Reload pick up the changed configuration
        sleep 3;

        # wait until process is synchronized
        $Selenium->WaitFor( JavaScript => 'return typeof($) === "function" && !$(".Notice").length' );

        # get process object
        my $ProcessObject = $Kernel::OM->Get('Kernel::System::ProcessManagement::DB::Process');

        # get process list
        my $List = $ProcessObject->ProcessList(
            UseEntities => 1,
            UserID      => $TestUserID,
        );

        # get process entity
        my %ListReverse = reverse %{$List};
        my $ProcessName = 'TestProcess';

        my $Process = $ProcessObject->ProcessGet(
            EntityID => $ListReverse{$ProcessName},
            UserID   => $TestUserID,
        );

        $Self->Is(
            $Process->{Name},
            'TestProcess',
            "Test process is creted"
        );

        # navigate to AgentTicketProcess screen
        $Selenium->VerifiedGet("${ScriptAlias}index.pl?Action=AgentTicketProcess");

        # select test process
        $Selenium->execute_script(
            "\$('#ProcessEntityID').val('$ListReverse{$ProcessName}').trigger('redraw.InputField').trigger('change');"
        );

        # wait until page has loaded, if necessary
        $Selenium->WaitFor( JavaScript => 'return typeof($) === "function" && $("#Subject").length' );

        # input process ticket subject and body
        my $SubjectRand = 'ProcessSubject-' . $Helper->GetRandomID();
        $Selenium->execute_script("\$('#QueueID').val('2').trigger('redraw.InputField').trigger('change');");
        $Selenium->find_element( "#Subject",  'css' )->send_keys($SubjectRand);
        $Selenium->find_element( "#RichText", 'css' )->send_keys('Test Process Body');

        # submit process
        $Selenium->find_element( "#Subject", 'css' )->VerifiedSubmit();

        # let mod_perl / Apache2::Reload pick up the changed configuration
        sleep 3;

        # get ticket object
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

        # get test process ticket ID
        my @TicketIDs = $TicketObject->TicketSearch(
            Result  => 'ARRAY',
            SortBy  => 'Age',
            OrderBy => 'Down',
            Limit   => 1,
            UserID  => 1,
        );

        my %Ticket = $TicketObject->TicketGet(
            TicketID => $TicketIDs[0],
            UserID   => 1,
        );

        $Self->Is(
            $Ticket{CreateBy},
            $TestUserID,
            "Test ticket process is creted"
        ) || die;

        # navigate to AgentTicketZoom screen of created test process
        $Selenium->VerifiedGet("${ScriptAlias}index.pl?Action=AgentTicketZoom;TicketID=$TicketIDs[0]");

        # verify there is 'Process Information' widget
        my $ParentElement = $Selenium->find_element( ".SidebarColumn", 'css' );
        $Self->Is(
            $Selenium->find_child_element( $ParentElement, '.Header>h2', 'css' )->get_text(),
            'Process Information',
            'Process Information widget is enabled',
        );

        # verify there are process informations in 'Process Information' widget
        $Self->True(
            $Selenium->find_element("//p[contains(\@title, \'TestProcess' )]"),
            "Process name found in Process Information widget"
        );
        $Self->True(
            $Selenium->find_element("//p[contains(\@title, \'Shipping' )]"),
            "Process activity found in Ticket Information widget"
        );

        # click on 'Priority' and switch screen
        $Selenium->find_element("//a[contains(\@href, \'Action=AgentTicketPriority;TicketID=$TicketIDs[0]' )]")
            ->click();

        $Selenium->WaitFor( WindowCount => 2 );
        my $Handles = $Selenium->get_window_handles();
        $Selenium->switch_to_window( $Handles->[1] );

        # wait until page has loaded, if necessary
        $Selenium->WaitFor( JavaScript => 'return typeof($) === "function" && $("#NewPriorityID").length' );

        # select '5 very high' priority to trigger next stage in process
        $Selenium->execute_script("\$('#NewPriorityID').val('5').trigger('redraw.InputField').trigger('change');");

        $Selenium->find_element( "#Subject",  'css' )->send_keys('TestSubject');
        $Selenium->find_element( "#RichText", 'css' )->send_keys('TestBody');
        $Selenium->find_element("//button[\@type='submit']")->click();

        # switch back screen
        $Selenium->WaitFor( WindowCount => 1 );
        $Selenium->switch_to_window( $Handles->[0] );

        # refresh screen
        $Selenium->VerifiedRefresh();

        # verify there is new activity in 'Process Information' widget
        $Self->True(
            $Selenium->find_element("//p[contains(\@title, \'Ordering complete' )]"),
            "Process activity found in Process Information widget"
        );

        # cleanup test data
        # delete test process ticket
        my $Success = $TicketObject->TicketDelete(
            TicketID => $TicketIDs[0],
            UserID   => $TestUserID,
        );

        $Self->True(
            $Success,
            "Process ticket ID $TicketIDs[0] is deleted",
        );

        # get needed objects
        my $ActivityObject       = $Kernel::OM->Get('Kernel::System::ProcessManagement::DB::Activity');
        my $ActivityDialogObject = $Kernel::OM->Get('Kernel::System::ProcessManagement::DB::ActivityDialog');

        # clean up activities
        for my $Item ( @{ $Process->{Activities} } ) {
            my $Activity = $ActivityObject->ActivityGet(
                EntityID            => $Item,
                UserID              => $TestUserID,
                ActivityDialogNames => 0,
            );

            # clean up activity dialogs
            for my $ActivityDialogItem ( @{ $Activity->{ActivityDialogs} } ) {
                my $ActivityDialog = $ActivityDialogObject->ActivityDialogGet(
                    EntityID => $ActivityDialogItem,
                    UserID   => $TestUserID,
                );

                # delete test activity dialog
                $Success = $ActivityDialogObject->ActivityDialogDelete(
                    ID     => $ActivityDialog->{ID},
                    UserID => $TestUserID,
                );
                $Self->True(
                    $Success,
                    "ActivityDialog $ActivityDialog->{Name} is deleted",
                );
            }

            # delete test activity
            $Success = $ActivityObject->ActivityDelete(
                ID     => $Activity->{ID},
                UserID => $TestUserID,
            );

            $Self->True(
                $Success,
                "Activity $Activity->{Name} is deleted",
            );
        }

        # get transition actions object
        my $TransitionActionsObject = $Kernel::OM->Get('Kernel::System::ProcessManagement::DB::TransitionAction');

        # clean up transition actions
        for my $Item ( @{ $Process->{TransitionActions} } ) {
            my $TransitionAction = $TransitionActionsObject->TransitionActionGet(
                EntityID => $Item,
                UserID   => $TestUserID,
            );

            # delete test transition action
            $Success = $TransitionActionsObject->TransitionActionDelete(
                ID     => $TransitionAction->{ID},
                UserID => $TestUserID,
            );

            $Self->True(
                $Success,
                "TransitionAction $TransitionAction->{Name} is deleted",
            );
        }

        # get transition object
        my $TransitionObject = $Kernel::OM->Get('Kernel::System::ProcessManagement::DB::Transition');

        # clean up transition
        for my $Item ( @{ $Process->{Transitions} } ) {
            my $Transition = $TransitionObject->TransitionGet(
                EntityID => $Item,
                UserID   => $TestUserID,
            );

            # delete test transition
            $Success = $TransitionObject->TransitionDelete(
                ID     => $Transition->{ID},
                UserID => $TestUserID,
            );

            $Self->True(
                $Success,
                "Transition $Transition->{Name} is deleted",
            );
        }

        # delete test process
        $Success = $ProcessObject->ProcessDelete(
            ID     => $Process->{ID},
            UserID => $TestUserID,
        );

        $Self->True(
            $Success,
            "Process $Process->{Name} is deleted",
        );

        # navigate to AdminProcessManagement screen
        $Selenium->VerifiedGet("${ScriptAlias}index.pl?Action=AdminProcessManagement");

        # synchronize process after deleting test process
        $Selenium->find_element("//a[contains(\@href, \'Subaction=ProcessSync' )]")->VerifiedClick();

        # make sure the cache is correct
        for my $Cache (
            qw (Ticket TicketSearch ProcessManagement_Activity ProcessManagement_ActivityDialog ProcessManagement_Transition ProcessManagement_TransitionAction )
            )
        {
            $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
                Type => $Cache,
            );
        }
    }

);

1;
